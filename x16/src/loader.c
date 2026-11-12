#include <stdint.h>
#include "apple2e.h"

/* Resident loader at $2000.  X16 KERNAL LOAD reads whole files, so scenes are
 * split at build time into two VRAM chunks and overlays are single PRG-like
 * binaries with a two-byte $3000 load address. */
#define LOAD_GAME_MAGIC    0xA5u
#define LOAD_HOWTO_MAGIC   0xA6u
#define LOAD_OPTIONS_MAGIC 0xA7u
#define QUIT_MAGIC         0xA8u
#define LOAD_INTRO_MAGIC   0xA9u
#define LOAD_TITLE_MAGIC   0x00u

static uint8_t score_buf[12];
static uint8_t fail_stage = '0';

static void lower_name(const char *s, uint8_t len) {
    uint8_t i;
    for (i = 0; i < len; ++i) {
        uint8_t c = (uint8_t)s[i];
        if (c >= 'A' && c <= 'Z') c = (uint8_t)(c + 32);
        x16_name[i] = c;
    }
    x16_namelen = len;
}

static uint8_t load_file(const char *name, uint8_t len, uint8_t sa,
                         uint8_t mode, uint8_t bank, uint16_t addr) {
    lower_name(name, len);
    x16_sa = sa;
    x16_mode = mode;
    x16_bank = bank;
    x16_addr = addr;
    x16_kload();
    return x16_err == 0;
}

/* X16 KERNAL VRAM LOAD is not reliable on every ROM/emulator combination.
 * Load the scene into banked RAM with the same headerless LOAD used by assets,
 * then stream it into VERA port 0.  Banks 50..59 are free here because the
 * loader runs before the game claims banks 30..39. */
#define SCENE_BANK 50u
static uint8_t load_scene(const char *prefix, uint8_t len) {
    uint8_t name[12];
    uint16_t lens[10];
    uint8_t i, chunks = 0;
    uint16_t j;
    uint32_t vram = 0;
    for (i = 0; i < len; ++i) name[i] = (uint8_t)prefix[i];
    name[len] = '.'; name[len + 1] = 'v'; name[len + 2] = '0';
    for (i = 0; i < 10; ++i) {
        name[len + 2] = (uint8_t)('0' + i);
        if (!load_file((const char *)name, (uint8_t)(len + 3u), 2, 0,
                       (uint8_t)(SCENE_BANK + i), 0xA000u)) {
            if (i == 0) return 0;
            break;
        }
        if (x16_end < 0xA000u) return 0;
        lens[i] = (uint16_t)(x16_end - 0xA000u);
        if (lens[i] > 8000u) return 0;
        ++chunks;
        if (lens[i] < 8000u) break;
    }
    if (!chunks) return 0;
    VERA.control = 0;
    for (i = 0; i < chunks; ++i) {
        *(volatile uint8_t *)0x00 = (uint8_t)(SCENE_BANK + i);
        for (j = 0; j < lens[i]; ++j, ++vram) {
            if ((vram & 0xFFFFu) == 0) {
                VERA.address_hi = (uint8_t)(VERA_INC_1 | (vram >> 16));
                VERA.address = 0;
            }
            VERA.data0 = *(volatile uint8_t *)(0xA000u + j);
        }
    }
    *(volatile uint8_t *)0x00 = X16_HUD_BANK;
    return 1;
}

static void scores(void) {
    uint8_t i, ok = 0;
    lower_name("HISCORE.DAT", 11);
    x16_sa = 2;
    x16_mode = 0;
    x16_bank = X16_HUD_BANK;
    x16_addr = (uint16_t)(uintptr_t)score_buf;
    x16_kload();
    if (!x16_err) {
        if (HISCORE_INIT != 0xA5u) {
            HIGH_SCORES[0] = HIGH_SCORES[1] = 0;
            if (score_buf[0] == 'F' && score_buf[1] == 'G'
                && score_buf[2] == 'H' && score_buf[3] == 1)
                for (i = 0; i < 8; ++i) ((volatile uint8_t *)HIGH_SCORES)[i] = score_buf[4 + i];
            HISCORE_INIT = 0xA5u;
            HISCORE_DIRTY = 0;
        } else if (!HISCORE_DIRTY) ok = 1;
    }
    if (!HISCORE_INIT) HISCORE_INIT = 0xA5u;
    if (HISCORE_DIRTY) {
        score_buf[0] = 'F'; score_buf[1] = 'G';
        score_buf[2] = 'H'; score_buf[3] = 1;
        for (i = 0; i < 8; ++i) score_buf[4 + i] = ((volatile uint8_t *)HIGH_SCORES)[i];
        lower_name("HISCORE.DAT", 11);
        x16_save_start = (uint16_t)(uintptr_t)score_buf;
        x16_save_end = (uint16_t)((uintptr_t)score_buf + 12u);
        x16_ksave();
        if (!x16_err) HISCORE_DIRTY = 0;
    }
    (void)ok;
}

static void fail(void) {
    static const char hex[] = "0123456789ABCDEF";
    uint8_t e = x16_err;
    x16_kputc(0x93);
    const char *s = "FREEGEMAS: LOAD ERROR ";
    while (*s) x16_kputc((uint8_t)*s++);
    x16_kputc(fail_stage);
    x16_kputc(' ');
    x16_kputc((uint8_t)hex[e >> 4]);
    x16_kputc((uint8_t)hex[e & 15]);
    x16_kputc(0x0D);
    for (;;) {}
}

int main(void) {
    uint8_t image;
    x16_irq_install();
    DETECTED_VERA = 1;
    if (SETTINGS_INIT != 0xA5u) {
        HISCORE_INIT = 0;
        HISCORE_DIRTY = 0;
        HIGH_SCORES[0] = HIGH_SCORES[1] = 0;
        SETTINGS_INIT = 0xA5u;
        MUSIC_SETTING = 1;
        SOUND_SETTING = 1;
        if (NEXT_IMAGE != LOAD_GAME_MAGIC && NEXT_IMAGE != LOAD_HOWTO_MAGIC
            && NEXT_IMAGE != LOAD_OPTIONS_MAGIC && NEXT_IMAGE != QUIT_MAGIC)
            NEXT_IMAGE = LOAD_INTRO_MAGIC;
    }
    scores();
    image = NEXT_IMAGE;
    if (image == QUIT_MAGIC) {
        NEXT_IMAGE = 0;
        SETTINGS_INIT = 0;
        x16_irq_remove();
        x16_kcint();
        x16_enter_basic();
    }
    if (image == LOAD_GAME_MAGIC) {
        fail_stage = 'G';
        NEXT_IMAGE = 0;
        if (!load_file("game", 4, 1, 0, 1, 0)) fail();
    } else if (image == LOAD_HOWTO_MAGIC) {
        fail_stage = 'H';
        if (!load_scene("howto", 5)) fail();
        NEXT_IMAGE = 0;
        if (!load_file("howto", 5, 1, 0, 1, 0)) fail();
    } else if (image == LOAD_OPTIONS_MAGIC) {
        fail_stage = 'O';
        if (!load_scene("options", 7)) fail();
        NEXT_IMAGE = 0;
        if (!load_file("options", 7, 1, 0, 1, 0)) fail();
    } else if (image == LOAD_INTRO_MAGIC) {
        fail_stage = 'I';
        NEXT_IMAGE = 0;
        if (!load_file("intro", 5, 1, 0, 1, 0)) fail();
    } else {
        fail_stage = 'T';
        if (!load_scene("title", 5)) fail();
        NEXT_IMAGE = 0;
        if (!load_file("title", 5, 1, 0, 1, 0)) fail();
    }
    ((void (*)(void))0x3000)();
    return 0;
}
