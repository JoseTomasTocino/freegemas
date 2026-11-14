/* Background music: streamed signed 8-bit PCM (MUSIC.PCM).
 *
 * VERA has a single PCM FIFO and the sound effects share it, so the game
 * feeds one 8-bit stream: music bytes read from disk plus the active effect,
 * added sample by sample. The source peaks fit signed 8-bit without wrapping;
 * PCM volume also leaves headroom for the doubled VERA bus in the emulators.
 *
 * The FIFO is kept about two VSYNC frames deep: enough slack for a slow match
 * cascade, but small enough that an effect is not audibly late.  A small RAM
 * ring is topped up from MUSIC.PCM every few frames; the disk is never read to
 * fill the FIFO directly.
 *
 * waitvsync returns without waiting when a frame overruns its VSYNC (a match
 * cascade, the music disk read, a full-board scan), so the 133/134 samples
 * fed per iteration lag the samples the VERA drains in real time.  The VERA
 * audio-low flag (ISR bit 3, FIFO below 1024) reports that depth live, so the
 * queue is topped back up to the target instead of trickling in one guessed
 * catch-up amount; the frame length no longer matters.
 *
 * The same sample count is the only real-time reference this machine has, so
 * it doubles as the game clock: music_frames_elapsed() converts the samples
 * fed back into VSYNC ticks.  Counting loop iterations instead ran the Time
 * Trial clock at half speed on long frames (the music finished while the
 * timer still read 1:24).
 */
#include <stdint.h>
#include "apple2e.h"
#include "music.h"
#include "sound.h"

#define MUSIC_SETTING (*(volatile uint8_t *)0x03F2)
#define MUSIC_RING   1024u       /* staging ring, one block plus slack */
#define MUSIC_BUFFER 1024u       /* samples queued (~128 ms at rate 21) */
#define MUSIC_RATE   21u         /* 21 * 25e6 / 512 / 128 = 8010.86 Hz */
#define MUSIC_VOLUME 0x0Du       /* mono 8-bit, volume 13 (38/64) */
#define MUSIC_CATCHUP 128u       /* samples fed per queue top-up step */
/* One VSYNC drains 8010.86 / 60 = 133.514 samples; thousandths keep the
 * sample counter integral, so it can double as the game's real-time clock. */
#define CLOCK_PER_FRAME 133514u

extern uint8_t mli_status;
extern void disk_read(uint16_t block, uint8_t *dest);
extern uint16_t disk_read_seq(uint16_t count, uint8_t *dest);
extern uint8_t disk_file(const char *name, uint8_t length, uint16_t *key, uint32_t *size);
extern void disk_close(void);
extern uint8_t disk_epoch(void);
extern void pcm_copy(void), pcm_mix(void);
extern uint16_t pcm_count;
extern uint8_t *pcm_pointer;
extern uint8_t *pcm_effect;
extern void psg_init(void), psg_tick(void), psg_stop(void), psg_restart(void);

static uint8_t ring[MUSIC_RING];
static const uint8_t silence[256];
static uint16_t ring_read, ring_count;
static uint32_t music_size, music_file_pos, music_mark;
static uint8_t music_ready, music_on, music_mark_ok;
static uint8_t pcm_playing_music;
static uint8_t music_epoch, music_fd;
static uint8_t budget_phase;
static uint32_t clock_acc;       /* samples fed x1000, thousandths of a frame */
static uint8_t clock_active;     /* the stream fed samples during this frame */

/* ProDOS closes the previous file whenever another one is opened, so the
 * epoch reported by main.c tells us that our refnum is gone. */
static uint8_t open_file(void) {
    uint16_t key;
    uint32_t size;
    if (music_fd && disk_epoch() == music_epoch) return 1;
    mli_status = 0;
    if (!disk_file("MUSIC.PCM", 9, &key, &size)) { music_fd = 0; return 0; }
    music_size = size;
    music_fd = 1;
    music_epoch = disk_epoch();
    music_file_pos = 0;
    music_mark = 0;
    music_mark_ok = 0;
    return 1;
}

static uint8_t read_block(void) {
    uint32_t offset;
    uint16_t want, got;
    if (!music_fd) return 0;
    if (music_file_pos >= music_size) music_file_pos = 0;   /* seamless loop */
    offset = music_file_pos;
    want = music_size - offset > MUSIC_RING ? MUSIC_RING : (uint16_t)(music_size - offset);
    if (music_mark_ok && offset == music_mark) {
        mli_status = 0;
        got = disk_read_seq(want, ring);
        if (!got) {             /* the mark may be unusable; restart from here */
            disk_read((uint16_t)(offset >> 9), ring);
            if (mli_status) return 0;
            got = music_size - offset > 512u ? 512u : (uint16_t)(music_size - offset);
        }
    } else {
        disk_read((uint16_t)(offset >> 9), ring);
        if (mli_status) return 0;
        got = music_size - offset > 512u ? 512u : (uint16_t)(music_size - offset);
    }
    if (!got) return 0;
    ring_read = 0;
    ring_count = got;
    music_file_pos = offset + got;
    music_mark = offset + got;
    music_mark_ok = 1;
    return 1;
}

static void engine_silence(void) {
    VERA.audio.control = 0x00;
    VERA.audio.rate = 0;
    VERA.audio.control = 0xA0;      /* reset the FIFO, stay muted */
}

/* Feed at most `budget` samples, mixing the active effect when one is playing.
 * Returns the samples the FIFO accepted, so the caller can count them.  The
 * VERA port 0 address is saved and restored because reading the effect stage
 * uses the same port. */
__attribute__((noinline)) static uint16_t feed(uint8_t use_music, uint16_t budget) {
    uint16_t total = 0;
    uint8_t ctrl = VERA.control, hi = VERA.address_hi;
    uint16_t address = VERA.address;
    while (budget) {
        uint16_t chunk, sent, room, ecount = 0;
        uint8_t *mptr, *eptr = 0;
        if (use_music) {
            if (!ring_count && !read_block()) break;
            if (!ring_count) break;
            chunk = ring_count > 255u ? 255u : ring_count;
            if (MUSIC_RING - ring_read < chunk) chunk = MUSIC_RING - ring_read;
            mptr = &ring[ring_read];
        } else {
            chunk = 255u;
            mptr = (uint8_t *)silence;
        }
        if (chunk > budget) chunk = budget;
        if (sound_remaining()) {
            eptr = sound_stage(chunk, &ecount);
            if (eptr) {
                /* The effect stage is 256 bytes, so its run must not wrap. */
                room = (uint16_t)(256u - ((uint16_t)(uintptr_t)eptr & 0xFFu));
                if (ecount > room) ecount = room;
                if (ecount < chunk) chunk = ecount;
            }
            if (!ecount) eptr = 0;
        }
        if (!chunk) break;
        pcm_count = chunk;
        pcm_pointer = mptr;
        if (eptr) { pcm_effect = eptr; pcm_mix(); }
        else pcm_copy();
        sent = (uint16_t)(chunk - pcm_count);
        if (use_music) {
            ring_read += sent;
            if (ring_read >= MUSIC_RING) ring_read = 0;
            ring_count -= sent;
        }
        if (eptr) sound_stage_commit(sent);
        budget -= sent;
        total += sent;
        if (sent < chunk) break;    /* FIFO full */
    }
    /* Restore control first: the address registers belong to whichever port
     * control selects, and the effect staging left it on port 0. */
    VERA.control = ctrl;
    VERA.address = address;
    VERA.address_hi = hi;
    return total;
}

__attribute__((noinline)) static void engine_start(uint8_t use_music) {
    VERA.audio.control = 0x20;
    VERA.audio.rate = 0;
    VERA.audio.control = 0xA0;      /* discard any stale samples */
    VERA.audio.control = MUSIC_VOLUME;
    feed(use_music, MUSIC_BUFFER);
    VERA.audio.rate = MUSIC_RATE;
    pcm_playing_music = use_music;
}

void music_init(void) {
    uint16_t key;
    uint32_t size;
    music_ready = 0;
    music_on = 0;
    pcm_playing_music = 0;
    music_fd = 0;
    ring_read = ring_count = 0;
    music_file_pos = 0;
    music_mark_ok = 0;
    budget_phase = 0;
    clock_acc = 0;
    clock_active = 0;
    if (MUSIC_SETTING == 2u) {
        /* PSG and preloaded effects do not depend on MUSIC.PCM. */
        music_ready = 1;
        psg_init();
        return;
    }
    /* Validate only: sound_init opens the effect files right after this and
     * would close ours anyway. */
    if (!disk_file("MUSIC.PCM", 9, &key, &size)) return;
    if (size < 512u || size > 0x180000u) { disk_close(); return; }
    music_size = size;
    music_ready = 1;
    disk_close();
}

static void pcm_stop(void) {
    engine_silence();
    music_on = 0;
    pcm_playing_music = 0;
    disk_close();
    music_fd = 0;
    ring_read = ring_count = 0;
    music_file_pos = 0;
    music_mark_ok = 0;
    clock_acc = 0;
    clock_active = 0;
}

__attribute__((noinline)) void music_stop(void) {
    pcm_stop();
    psg_stop();
}

__attribute__((noinline)) void music_restart(void) {
    music_file_pos = 0;
    music_mark_ok = 0;
    ring_read = ring_count = 0;
    psg_restart();
}

/* Real time, measured in VSYNC ticks, from the samples the FIFO drained.
 * Returns 0 when less than a frame has been paid in, so the caller can
 * accumulate; a frame with no stream at all still counts as one tick. */
__attribute__((noinline)) uint8_t music_frames_elapsed(void) {
    uint8_t n;
    if (!clock_active) return 1;
    /* Usually one or two frames are due. Repeated subtraction avoids a
     * costly 32-bit divide and multiply in every 65C02 animation frame. */
    n = 0;
    while (clock_acc >= CLOCK_PER_FRAME && n != 255u) {
        clock_acc -= CLOCK_PER_FRAME;
        ++n;
    }
    clock_active = 0;
    return n;
}

__attribute__((noinline)) void music_tick(void) {
    uint8_t music = MUSIC_SETTING == 1u;
    uint16_t total;
    if (MUSIC_SETTING == 2u) psg_tick();
    if (!music_ready) return;
    if (music_on && pcm_playing_music != music) pcm_stop();
    if (!music && !sound_remaining()) {
        /* Effects are already queued in the FIFO; let the tail play before
         * resetting it when PSG or OFF mode has no PCM music. */
        if (music_on && (VERA.audio.control & 0x40u)) pcm_stop();
        return;
    }
    if (music) {
        if (!open_file()) { music_ready = 0; music_stop(); return; }
        if (!music_on) { engine_start(1); music_on = 1; return; }
    } else if (!music_on) {
        engine_start(0);
        music_on = 1;
        return;
    }
    /* An empty FIFO means a frame overran the buffer; refill it rather than
     * trickling a frame's worth back and leaving the stream starved.  The
     * samples are queued for later, not played since the last tick, so they
     * do not count as elapsed time. */
    if (VERA.audio.control & 0x40u) {
        feed(music, MUSIC_BUFFER);
        return;
    }
    /* 133/134 alternately averages the 133.51 samples one VSYNC drains. */
    budget_phase ^= 1u;
    total = feed(music, (uint16_t)(133u + budget_phase));
    /* A frame that overran its VSYNC drained more than one frame's worth, so
     * top the queue back up to the target depth.  The audio-low flag is the
     * live FIFO level (<1024), so this loop pays exactly the shortfall and
     * never depends on guessing how long the frame was. */
    while (VERA.irq_flags & VERA_IRQ_AUDIO_LOW) {
        uint16_t sent;
        VERA.irq_flags = VERA_IRQ_AUDIO_LOW;    /* clear a latched flag */
        sent = feed(music, MUSIC_CATCHUP);
        total += sent;
        if (sent < MUSIC_CATCHUP) break;        /* FIFO full or stream dry */
    }
    clock_acc += (uint32_t)total * 1000u;
    clock_active = 1;
}
