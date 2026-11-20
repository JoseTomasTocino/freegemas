/* FREEGEMAS.SYSTEM: resident ProDOS loader.  It is intentionally tiny: it
 * loads segmented images at $3000 through a page-3 trampoline.
 * The loaded program may return here because this SYS image remains at $2000.
 */
#include <stdint.h>
#include "hiscore.h"

extern uint8_t mli_status;
extern uint8_t mli_open_params[], mli_close_params[], mli_read_params[];
extern uint8_t mli_write_params[], mli_mark_params[], mli_prefix_params[], mli_eof_params[];
extern void mli_open(void), mli_close(void), mli_read(void), mli_write(void);
extern void mli_set_mark(void), mli_get_prefix(void), mli_get_eof(void);
extern void mli_quit(void);
extern const uint8_t trampoline_src[], trampoline_src_end[];
extern void launch_image(void);
extern uint16_t scene_src, scene_count, scene_data_port;
extern void scene_copy(void);
extern void clear_text(void);

#define NEXT_IMAGE (*(volatile uint8_t *)0x03F0)
#define LOAD_GAME_MAGIC 0xA5u
#define LOAD_HOWTO_MAGIC 0xA6u
#define LOAD_OPTIONS_MAGIC 0xA7u
#define QUIT_MAGIC 0xA8u
#define LOAD_INTRO_MAGIC 0xA9u
#define SETTINGS_INIT (*(volatile uint8_t *)0x03F4)
#define DETECTED_VERA (*(volatile uint8_t *)0x03EC)

static uint8_t * const buf = (uint8_t *)0x0C00;
static uint8_t * const path_buf = (uint8_t *)0x0B00;

/* Keep loader failures observable even before VERA is initialized. */
static void status(const char *s) {
    volatile uint8_t *p = (volatile uint8_t *)0x0400;
    *(volatile uint8_t *)0xC051 = 0; *(volatile uint8_t *)0xC054 = 0;
    clear_text();
    while (*s) *p++ = (uint8_t)(*s++ | 0x80);
}
static void fail(const char *s) { status(s); for (;;) {} }
static void fail_code(const char *s, uint8_t code) {
    volatile uint8_t *p = (volatile uint8_t *)0x0400;
    uint8_t n;
    status(s);
    while (*s++) ++p;
    n = (uint8_t)(code >> 4); *p++ = (uint8_t)((n < 10 ? '0' + n : 'A' + n - 10) | 0x80);
    n = (uint8_t)(code & 15); *p = (uint8_t)((n < 10 ? '0' + n : 'A' + n - 10) | 0x80);
    for (;;) {}
}

static uint8_t probe_vera(uint16_t base) {
    volatile uint8_t *r = (volatile uint8_t *)base;
    r[5] = 0;
    /* ROM shadows/plain RAM can echo writes too. Real VERA must advance
     * its VRAM address after a DATA0 read with increment 1 enabled. */
    r[0]=r[1]=0;r[2]=0x10;
    (void)r[3];
    return r[0]==1;
}

static uint8_t open_prefix_file(const char *name) {
    uint8_t i, len;
    uintptr_t p = (uintptr_t)path_buf;
    mli_prefix_params[1] = (uint8_t)p;
    mli_prefix_params[2] = (uint8_t)(p >> 8);
    mli_get_prefix();
    if (mli_status || path_buf[0] > 63) return 0;
    len = path_buf[0];
    if (len && path_buf[len] != '/') {
        if (len >= 63) return 0;
        path_buf[++len] = '/';
    }
    for (i = 0; name[i]; ++i) {
        if (len >= 64) return 0;
        path_buf[++len] = (uint8_t)name[i];
    }
    path_buf[0] = len;
    p = (uintptr_t)path_buf;
    mli_open_params[1] = (uint8_t)p;
    mli_open_params[2] = (uint8_t)(p >> 8);
    /* ProDOS needs a separate 1 KB, page-aligned I/O buffer.  Keep file
       payload reads at $0C00, away from ProDOS directory/file bookkeeping. */
    mli_open_params[3] = 0x00;
    mli_open_params[4] = 0xB8;
    mli_open_params[5] = 0;
    mli_open();
    return mli_status == 0;
}

static uint8_t read_file(uint8_t ref, uint32_t offset, uint16_t count,
                         uint8_t *dest) {
    uintptr_t p;
    mli_mark_params[1] = ref;
    mli_mark_params[2] = (uint8_t)offset;
    mli_mark_params[3] = (uint8_t)(offset >> 8);
    mli_mark_params[4] = (uint8_t)(offset >> 16);
    mli_set_mark();
    if (mli_status) fail("MARK ERROR");
    p = (uintptr_t)dest;
    mli_read_params[1] = ref;
    mli_read_params[2] = (uint8_t)p;
    mli_read_params[3] = (uint8_t)(p >> 8);
    mli_read_params[4] = (uint8_t)count;
    mli_read_params[5] = (uint8_t)(count >> 8);
    mli_read_params[6] = mli_read_params[7] = 0;
    mli_read();
    if (mli_status) fail_code("READ ERROR ", mli_status);
    if (mli_read_params[6] != (uint8_t)count
        || mli_read_params[7] != (uint8_t)(count >> 8)) fail("READ SHORT");
    return 1;
}

/* The title art is streamed while the SYS image still owns the MLI state.
 * TITLE.BIN is then only a small palette/input program below $2000. */
static uint8_t stream_scene(uint8_t vera_slot, const char *scene) {
    uint8_t ref, run = 0, need_count = 1, raw = 0;
    uint16_t p;
    uint32_t eof, done = 0;
    volatile uint8_t *v = (volatile uint8_t *)(vera_slot == 2 ? 0xC200 : 0xC400);
    if (!open_prefix_file(scene)) fail("SCN OPEN");
    ref = mli_open_params[5];
    mli_eof_params[1] = ref;
    mli_get_eof();
    if (mli_status) { mli_close_params[1] = ref; mli_close(); fail("SCN EOF"); }
    eof = (uint32_t)mli_eof_params[2] | ((uint32_t)mli_eof_params[3] << 8)
        | ((uint32_t)mli_eof_params[4] << 16);
    if (!eof) { mli_close_params[1] = ref; mli_close(); fail("SCN EMPTY"); }
    v[5] = 0; v[2] = 0x10; v[1] = 0; v[0] = 0; /* DATA0, VRAM $00000, +1 */
    scene_data_port=(uint16_t)(v+3);
    while (done < eof) {
        uint16_t n = eof - done > 512u ? 512u : (uint16_t)(eof - done);
        if (!read_file(ref, done, n, buf)) {
            mli_close_params[1] = ref; mli_close(); fail("SCN READ");
        }
        if(raw){scene_src=(uint16_t)buf;scene_count=n;scene_copy();}
        else for (p = 0; p < n; ++p) {
            uint8_t byte = buf[p];
            if(raw) v[3]=byte;
            else if (need_count) { run = byte; need_count = 0; }
            else if(!run && done==0 && p==1 && byte==0){
                raw=1;need_count=1;
                scene_src=(uint16_t)(buf+2);scene_count=n-2u;scene_copy();break;
            }
            else { while (run--) v[3] = byte; need_count = 1; }
        }
        done += n;
    }
    mli_close_params[1] = ref; mli_close();
    return need_count;
}

static void scores(void) {
    uint8_t i, ref, saved = 0;
    uintptr_t p;
    if (!open_prefix_file("HISCORE.DAT")) return;
    ref = mli_open_params[5];
    if (!read_file(ref, 0, 12, buf)) {
        mli_close_params[1] = ref; mli_close(); return;
    }
    if (HISCORE_INIT != 0xA5u) {
        HIGH_SCORES[0] = HIGH_SCORES[1] = 0;
        if (buf[0]=='F' && buf[1]=='G' && buf[2]=='H' && buf[3]==1)
            for(i=0;i<8;i++) ((volatile uint8_t *)0x03E0)[i]=buf[4+i];
        HISCORE_DIRTY=0; HISCORE_INIT=0xA5u;
    } else if(HISCORE_DIRTY) {
        buf[0]='F';buf[1]='G';buf[2]='H';buf[3]=1;
        for(i=0;i<8;i++)buf[4+i]=((volatile uint8_t *)0x03E0)[i];
        mli_mark_params[1] = ref;
        mli_mark_params[2] = mli_mark_params[3] = mli_mark_params[4] = 0;
        mli_set_mark();
        p = (uintptr_t)buf;
        mli_write_params[1] = ref;
        mli_write_params[2] = (uint8_t)p;
        mli_write_params[3] = (uint8_t)(p >> 8);
        mli_write_params[4] = 12;
        mli_write_params[5] = mli_write_params[7] = 0;
        mli_write_params[6] = 0;
        if (!mli_status) mli_write();
        if(!mli_status && mli_write_params[6] == 12 && !mli_write_params[7]) saved = 1;
    }
    mli_close_params[1] = ref; mli_close();
    if (saved) HISCORE_DIRTY=0;
}

int main(void) {
    uint8_t slot, count, image, ref;
    uint16_t i;
    uint16_t blocks;
    uint32_t eof;
    const char *name;
    uint8_t *trampoline;
    volatile uint8_t *vera;
    status("FREEGEMAS LOADER");
    if (SETTINGS_INIT != 0xA5u) {
        HISCORE_INIT=0; HISCORE_DIRTY=0;
        HIGH_SCORES[0]=HIGH_SCORES[1]=0;
        SETTINGS_INIT = 0xA5u;
        *(volatile uint8_t *)0x03F2 = 1;
        *(volatile uint8_t *)0x03F3 = 1;
        if(NEXT_IMAGE!=LOAD_GAME_MAGIC && NEXT_IMAGE!=LOAD_HOWTO_MAGIC &&
           NEXT_IMAGE!=LOAD_OPTIONS_MAGIC && NEXT_IMAGE!=QUIT_MAGIC)
            NEXT_IMAGE=LOAD_INTRO_MAGIC;
    }
    if (probe_vera(0xC200)) slot = 2;
    else if (probe_vera(0xC400)) slot = 4;
    else {slot=0;NEXT_IMAGE=LOAD_INTRO_MAGIC;}
    DETECTED_VERA=slot;

    if (!open_prefix_file("FREEGEMAS")) fail(" GAME DIRECTORY");
    mli_close_params[1] = mli_open_params[5]; mli_close();

    /* Hide the previous VERA frame before either scene is streamed.  Without
       this, returning from game shows title pixels through the game palette. */
    if(slot){
    vera = (volatile uint8_t *)(slot == 2 ? 0xC200 : 0xC400);
    vera[5] = 0;                    /* DCSEL 0 */
    vera[9] = 0;                    /* DC_VIDEO: output/layers/sprites off */
    scores();
    }

    image = NEXT_IMAGE;
    if(image==QUIT_MAGIC){
        if(HISCORE_DIRTY) fail("HIGH SCORE SAVE FAILED");
        NEXT_IMAGE=0;
        SETTINGS_INIT=0;        /* A later launch from Bitsy Bye is a new boot. */
        mli_quit();
    }
    if(image==LOAD_GAME_MAGIC){status("LOADING GAME...");name=slot==4?"GAME4.BIN":"GAME.BIN";}
    else if(image==LOAD_HOWTO_MAGIC){status("LOADING HOW TO PLAY...");name=slot==4?"HOWTO4.BIN":"HOWTO.BIN";}
    else if(image==LOAD_OPTIONS_MAGIC){status("LOADING OPTIONS...");name=slot==4?"OPTION4.BIN":"OPTION.BIN";}
    else if(image==LOAD_INTRO_MAGIC){name=slot==4?"INTRO4.BIN":"INTRO.BIN";}
    else{status("LOADING TITLE...");name=slot==4?"TITLE4.BIN":"TITLE.BIN";}
    NEXT_IMAGE = 0;
    if(image!=LOAD_GAME_MAGIC && image!=LOAD_INTRO_MAGIC){const char *scene=image==LOAD_HOWTO_MAGIC?"HOWTO.RLE":image==LOAD_OPTIONS_MAGIC?"OPTION.RLE":"TITLE.RLE";if(!stream_scene(slot,scene))fail(" SCENE");}
    if (!open_prefix_file(name)) fail(" FILE");
    ref = mli_open_params[5];
    mli_eof_params[1] = ref;
    mli_get_eof();
    if (mli_status) fail(" EOF");
    eof = (uint32_t)mli_eof_params[2] | ((uint32_t)mli_eof_params[3] << 8)
        | ((uint32_t)mli_eof_params[4] << 16);
    if (!eof) fail(" FILE");
    if(eof > 0x8800u) fail(" IMAGE TOO LARGE");
    blocks = (uint16_t)((eof + 511u) / 512u);
    if (blocks == 0 || blocks > 255) fail(" SIZE");

    /* Permit MLI reads into the $3000-$B7FF image range. */
    for (i = 1; i < 23; ++i) ((volatile uint8_t *)0xBF58)[i] = 0;
    count = (uint8_t)(trampoline_src_end - trampoline_src);
    trampoline = (uint8_t *)0x0300;
    for (i = 0; i < count; ++i) trampoline[i] = trampoline_src[i];
    *(volatile uint8_t *)0x03C1 = ref;
    *(volatile uint8_t *)0x03C2 = 0x00;
    *(volatile uint8_t *)0x03C3 = 0x30;
    *(volatile uint8_t *)0x03C4 = 0x00;
    *(volatile uint8_t *)0x03C5 = 0x02;
    *(volatile uint8_t *)0x03D0 = 1;
    *(volatile uint8_t *)0x03D1 = ref;
    *(volatile uint8_t *)0x03C8 = (uint8_t)blocks;
    launch_image();
    return 0;
}
