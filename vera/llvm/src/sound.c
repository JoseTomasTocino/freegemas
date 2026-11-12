/* Original PCM sound effects, preloaded into VERA VRAM as signed 8-bit mono
 * samples at the music stream rate (VERA rate 21, 8010.86 Hz).
 *
 * VERA has a single PCM FIFO, so effects cannot use it on their own while the
 * music plays.  Instead music_tick() asks for a block of staged effect samples
 * and adds them to the music stream.  Peaks are limited at build time (music
 * 0.70, effects 0.29 full scale) so the signed sum never wraps.
 */
#include "sound.h"
#include "loading.h"
#include "apple2e.h"
#define SOUND_SETTING (*(volatile uint8_t *)0x03F3)
#define EFFECT_VRAM 0x14800u
#define EFFECT_STAGE 256u
extern uint8_t mli_status;
extern void disk_read(uint16_t block, uint8_t *dest);
extern uint8_t disk_file(const char *name, uint8_t len, uint16_t *key, uint32_t *size);
typedef struct { uint32_t offset; uint16_t length; } Sample;
static Sample samples[5];
/* Disk/PCM staging page shared with the scene and music loaders. */
static uint8_t *const buffer = (uint8_t *)0x0C00;
static uint8_t stage[EFFECT_STAGE];
static uint16_t stage_read, stage_write;
static uint32_t effect_source;      /* absolute VRAM address of the next fetch */
static uint16_t effect_remaining;
static uint8_t ready;
uint16_t pcm_count;
uint8_t *pcm_pointer;
uint8_t *pcm_effect;
extern void pcm_stage(void);

__attribute__((noinline)) void sound_init(void) {
    static const char *const names[5] = {
        "SELECT.PCM", "FALL.PCM", "MATCH1.PCM", "MATCH2.PCM", "MATCH3.PCM" };
    uint8_t n;
    uint32_t total = 0;
    ready = 0;
    effect_remaining = 0;
    stage_read = stage_write = 0;
    for (n = 0; n < 5; ++n) {
        uint16_t key, block = 0;
        uint32_t size, done = 0;
        if (!disk_file(names[n], n == 1 ? 8u : 10u, &key, &size)) return;
        if (!size || size > 4096u) return;
        samples[n].offset = EFFECT_VRAM + total;
        samples[n].length = (uint16_t)size;
        while (done < size) {
            uint16_t count = size - done > 512u ? 512u : (uint16_t)(size - done);
            uint16_t i;
            uint32_t at = (uint32_t)samples[n].offset + done;
            disk_read(block++, buffer);
            if (mli_status) return;
            VERA.control = 0;
            VERA.address = (uint16_t)at;
            VERA.address_hi = (uint8_t)(VERA_INC_1 | (at >> 16));
            for (i = 0; i < count; ++i) VERA.data0 = buffer[i];
            done += count;
            loading_step();
        }
        total += size;
    }
    ready = 1;
}

__attribute__((noinline)) void sound_stop(void) {
    effect_remaining = 0;
    stage_read = stage_write = 0;
}

__attribute__((noinline)) void sound_play(uint8_t effect) {
    uint8_t sample;
    if (!ready || !SOUND_SETTING) return;
    switch (effect) {
        case SFX_SELECT: sample = 0; break;
        case SFX_FALL:   sample = 1; break;
        case SFX_MATCH1: sample = 2; break;
        case SFX_MATCH2: sample = 3; break;
        case SFX_MATCH3: sample = 4; break;
        default: return;
    }
    sound_stop();
    effect_source = samples[sample].offset;
    effect_remaining = samples[sample].length;
}

uint16_t sound_remaining(void) {
    return effect_remaining;
}

/* Bring up to `max` staged effect samples into RAM so the mixer can add them
 * to a contiguous music run.  VERA has two address ports selected by the
 * control register, so the staging read borrows port 0 while the graphics code
 * may be using port 1 (or the other way round): both the control register and
 * port 0's address/increment are put back before returning. */
uint8_t *sound_stage(uint16_t max, uint16_t *count) {
    uint16_t n, take;
    uint32_t at;
    uint8_t ctrl, hi;
    uint16_t low;
    *count = 0;
    if (!effect_remaining) return 0;
    if (stage_read == stage_write) {
        take = effect_remaining > EFFECT_STAGE ? EFFECT_STAGE : effect_remaining;
        at = effect_source;
        ctrl = VERA.control;
        VERA.control = 0;
        hi = VERA.address_hi;
        low = VERA.address;
        VERA.address = (uint16_t)at;
        VERA.address_hi = (uint8_t)(VERA_INC_1 | (at >> 16));
        pcm_pointer = stage;
        pcm_count = take;
        pcm_stage();
        VERA.address = low;
        VERA.address_hi = hi;
        VERA.control = ctrl;
        effect_source += take;
        stage_read = 0;
        stage_write = take;
    }
    n = (uint16_t)(stage_write - stage_read);
    if (n > effect_remaining) n = effect_remaining;
    if (n > max) n = max;
    *count = n;
    return stage + stage_read;
}

void sound_stage_commit(uint16_t n) {
    stage_read = (uint16_t)(stage_read + n);
    effect_remaining = (uint16_t)(effect_remaining - n);
}
