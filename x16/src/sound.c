/* Original PCM sound effects, preloaded into banked RAM at $A000 in banks
 * 24..28 as signed 16-bit mono samples at 8010.86 Hz (VERA rate 21).
 *
 * Music is a 16-bit ZCM stream; music_tick() mixes these effect samples into
 * the music samples before the combined run is written to the PCM FIFO.  The
 * effects used to be 8-bit, which at their low original level left only a few
 * effective bits and made every match sound sandy.  Keeping them 16-bit and
 * giving each effect its own bank also avoids the old 8192-byte bank overflow
 * that truncated MATCH3.
 */
#include "sound.h"
#include "loading.h"
#include "apple2e.h"
#define EFFECT_FIRST_BANK 24u
#define EFFECT_BASE 0xA000u
/* One feed call can carry up to 510 bytes (255 samples) while catching up.
 * The old 320-byte (160-sample) stage covered only part of that call, so the
 * rest of the run was music-only and the effect sounded chopped. */
#define EFFECT_STAGE_BYTES 512u
#define EFFECT_STAGE_SAMPLES (EFFECT_STAGE_BYTES / 2u)
extern uint8_t mli_status;
extern void disk_read(uint16_t block, uint8_t *dest);
extern uint8_t disk_file(const char *name, uint8_t len, uint16_t *key, uint32_t *size);
typedef struct { uint8_t bank; uint16_t length; } Sample;
static Sample samples[5];
/* Disk/PCM staging page shared with the scene and music loaders. */
static uint8_t *const buffer = (uint8_t *)0x0C00;
/* $0F00 is the effects state page; keep the 512-byte effect stage below the
 * loader at $2000 and clear of that page. */
static uint8_t *const stage = (uint8_t *)0x1000u;
static uint16_t stage_read, stage_write;
static uint32_t effect_source;      /* byte offset of the next fetch in its bank */
static uint16_t effect_remaining;   /* samples left */
static uint8_t effect_bank;
static uint8_t ready;
uint16_t pcm_count;
uint8_t *pcm_pointer;

__attribute__((noinline)) void sound_init(void) {
    static const char *const names[5] = {
        "SELECT.PCM", "FALL.PCM", "MATCH1.PCM", "MATCH2.PCM", "MATCH3.PCM" };
    uint8_t n;
    ready = 0;
    effect_remaining = 0;
    stage_read = stage_write = 0;
    for (n = 0; n < 5; ++n) {
        uint16_t key, block = 0;
        uint32_t size, done = 0;
        if (!disk_file(names[n], n == 1 ? 8u : 10u, &key, &size)) return;
        if (!size || size > 8192u || (size & 1u)) return;
        samples[n].bank = (uint8_t)(EFFECT_FIRST_BANK + n);
        samples[n].length = (uint16_t)(size / 2u);
        while (done < size) {
            uint16_t count = size - done > 512u ? 512u : (uint16_t)(size - done);
            uint16_t i;
            disk_read(block++, buffer);
            if (mli_status) return;
            *(volatile uint8_t *)0x00 = samples[n].bank;
            for (i = 0; i < count; ++i)
                *(volatile uint8_t *)(EFFECT_BASE + done + i) = buffer[i];
            *(volatile uint8_t *)0x00 = X16_HUD_BANK;
            done += count;
            loading_step();
        }
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
    effect_bank = samples[sample].bank;
    effect_source = 0;
    effect_remaining = samples[sample].length;
}

uint16_t sound_remaining(void) {
    return effect_remaining;
}

/* Bring up to `max` staged effect samples into RAM so the mixer can add them
 * to a contiguous music run.  Each effect lives at the start of its own bank,
 * so a full 2403-sample match (4806 bytes) never crosses $BFFF. */
uint8_t *sound_stage(uint16_t max, uint16_t *count) {
    uint16_t take, bytes;
    *count = 0;
    if (!effect_remaining) return 0;
    /* Every caller consumes the returned samples in the same music run.
       Load a fresh, complete slice each time instead of returning a one-sample
       leftover from a 512-byte stage.  The old leftover path left most of the
       next 255-sample run without effect data, which is heard as choppy,
       intermittent match sounds. */
    take = effect_remaining > max ? max : effect_remaining;
    if (take > EFFECT_STAGE_SAMPLES) take = EFFECT_STAGE_SAMPLES;
    bytes = (uint16_t)(take * 2u);
    *(volatile uint8_t *)0x00 = effect_bank;
    {
        uint16_t i;
        for (i = 0; i < bytes; ++i)
            stage[i] = *(volatile uint8_t *)(EFFECT_BASE + effect_source + i);
    }
    *(volatile uint8_t *)0x00 = X16_HUD_BANK;
    effect_source += bytes;
    stage_read = 0;
    stage_write = bytes;
    *count = take;
    return stage;
}

void sound_stage_commit(uint16_t n) {
    effect_remaining = (uint16_t)(effect_remaining - n);
}
