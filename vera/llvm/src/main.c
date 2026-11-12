#include <stdint.h>
#include "apple2e.h"
#include "board.h"
#include "game_palette.h"
#include "hiscore.h"
#include "effects.h"
#include "random_seed.h"
#include "sound.h"
#include "music.h"
#include "mouse.h"
#include "loading.h"
#include "loading_data.h"

static uint16_t loading_done,loading_total;
static uint8_t loading_active,loading_percent;
static void loading_draw(uint8_t percent) {
    volatile uint8_t *p=(volatile uint8_t *)0x0480;
    uint8_t i,filled=percent/5u;
    p[0]='['|128u;
    for(i=0;i<20;i++)p[i+1]=(i<filled?'#':'-')|128u;
    p[21]=']'|128u;p[22]=0xA0;
    p[23]=(percent==100?'1':' ')|128u;
    p[24]=(percent>=10?'0'+(percent/10u)%10u:' ')|128u;
    p[25]=('0'+percent%10u)|128u;p[26]='%'|128u;
}
void loading_stage(const char *name) {
    volatile uint8_t *p=(volatile uint8_t *)0x0500;uint8_t i;
    if(!loading_active)return;
    for(i=0;i<40;i++)p[i]=0xA0;
    while(*name)*p++=*name++|128u;
}
void loading_step(void) {
    uint8_t percent;
    if(!loading_active)return;
    if(loading_done<loading_total)++loading_done;
    percent=(uint8_t)((uint32_t)loading_done*99u/loading_total);
    if(percent!=loading_percent){loading_percent=percent;loading_draw(percent);}
}

/* Original rules engine + persistent gem sprites over a pristine bitmap. */
static Board board;
static Board before_fall;
static uint8_t fall_gem[64];
static uint8_t fall_rows[64];
static int16_t fall_sy[64];
static uint16_t fall_dy[64];
static uint8_t cursor_x = 3, cursor_y = 3, selected = 0, select_x, select_y;
static uint32_t score;
static uint8_t displayed_digits[10], displayed_count;
static uint8_t displayed_time[4], time_display_valid;
static uint8_t hint_used;
static uint8_t time_left, time_frames, timer_active, game_over, resolving;
static uint8_t move_check_frames;
#define high_score HIGH_SCORES[GAME_MODE ? 1 : 0]
static uint8_t app_mode; /* 0=title, 1=game */
static uint8_t mouse_was_down;
static uint8_t mouse_drag;
static uint16_t mouse_last_x;
static uint8_t mouse_last_y;
#define NEXT_IMAGE (*(volatile uint8_t *)0x03F0)
#define GAME_MODE (*(volatile uint8_t *)0x03F1)

static void timer_frame(void);
static void show_game_over(void);

extern uint8_t mli_status;
extern uint8_t mli_open_params[], mli_close_params[], mli_read_params[];
extern uint8_t mli_mark_params[], mli_prefix_params[], mli_eof_params[];
extern void mli_open(void), mli_close(void), mli_read(void);
extern void mli_set_mark(void), mli_get_prefix(void), mli_get_eof(void);

#define GEM_X(c) ((uint16_t)(93u + (uint16_t)(c) * 26u))
#define GEM_Y(r) ((uint16_t)(13u + (uint16_t)(r) * 26u))

static void frame_work(void) {
    effects_tick();
    music_tick();
    timer_frame();
}

/* Long CPU-bound work (a full-board scan, a reshuffle) runs for many VSYNCs
 * without returning to the main loop, which would leave the PCM queue to
 * drain dry and the clock short.  Pay one frame's work from wherever the
 * VSYNC latch is picked up; the timer is left to the main loop so a scan
 * never re-enters the game-over path. */
void frame_pump(void) {
    if (VERA.irq_flags & VERA_IRQ_VSYNC) {
        VERA.irq_flags = VERA_IRQ_VSYNC;
        effects_tick();
        music_tick();
    }
}

static void waitvsync(void) {
    while ((VERA.irq_flags & VERA_IRQ_VSYNC) == 0) {}
    VERA.irq_flags = VERA_IRQ_VSYNC;
    frame_work();
}

static void vram_at(uint32_t address) {
    VERA.control = 0;
    VERA.address_hi = (uint8_t)(VERA_INC_1 | (address >> 16));
    VERA.address = (uint16_t)address;
}

/* Game Over reset reloads the pristine scene; former backups now hold PCM. */
#define SPRITE_PATTERNS 0x12C00u
static uint8_t score_backup[17u*77u],time_backup[15u*48u];
#define HEADER_MAP      0x1A800u
#define HEADER_TILES    0x1B800u

static void vram1_at(uint32_t address) {
    VERA.control = 1;
    VERA.address_hi = (uint8_t)(VERA_INC_1 | (address >> 16));
    VERA.address = (uint16_t)address;
    VERA.control = 0;
}

/* Game-over text (y=57-78, 88-108, 119-125) is drawn onto the bitmap.
 * On reset, erase_game_over() is a no-op: the 32px gem sprites on a 26px
 * pitch fully overlap and cover the entire board bitmap area after
 * animate_fall() completes, so text pixels are hidden naturally.
 * (Attempting to backup/restore that region in VRAM fails because there
 * is no 16 KB contiguous free area -- cursor/PCM patterns fill 0x14800+.) */
static void erase_game_over(void) { /* no-op -- gems cover the bitmap */ }


/* Layer 1 masks only the 16px top border, above z=2 gems. New sprites can
 * enter smoothly from negative Y without spilling across the board header.
 * Tile 0 is transparent everywhere else; cursor/particles at z=3 remain above. */
static void header_mask(void) {
    uint8_t x,y,row,col;
    uint16_t i;
    vram_at(HEADER_TILES);
    for(i=0;i<64;i++)VERA.data0=0;
    for(y=0;y<2;y++)for(x=0;x<40;x++)for(row=0;row<8;row++){
        vram1_at((uint32_t)(y*8u+row)*320u+x*8u);
        for(col=0;col<8;col++)VERA.data0=VERA.data1;
    }
    vram_at(HEADER_MAP);
    for(y=0;y<32;y++)for(x=0;x<64;x++){
        VERA.data0=y<2 && x<40 ? (uint8_t)(1u+y*40u+x):0;
        VERA.data0=0;
    }
    VERA.layer1.config=0x13; /* 64x32, 8bpp 8x8 tiles */
    VERA.layer1.mapbase=(uint8_t)(HEADER_MAP>>9);
    VERA.layer1.tilebase=(uint8_t)(HEADER_TILES>>9);
    VERA.layer1.hscroll=0;VERA.layer1.vscroll=0;
}

static void backup_score_panel(void) {
    uint8_t row, col;
    for (row = 0; row < 17; ++row) {
        vram1_at((uint32_t)(50u + row) * 320u + 7u);
        for (col = 0; col < 77; ++col) score_backup[(uint16_t)row*77u+col]=VERA.data1;
    }
}

static void backup_time_digits(void) {
    uint8_t row, col;
    for (row = 0; row < 15; ++row) {
        vram1_at((uint32_t)(98u + row) * 320u + 31u);
        for (col = 0; col < 48; ++col) time_backup[(uint16_t)row*48u+col]=VERA.data1;
    }
}

static const uint8_t score_digits[10][7] = {
    {14,17,19,21,25,17,14}, {4,12,4,4,4,4,14},
    {14,17,1,2,4,8,31}, {30,1,1,14,1,1,30},
    {2,6,10,18,31,2,2}, {31,16,16,30,1,1,30},
    {14,16,16,30,17,17,14}, {31,1,2,4,8,8,8},
    {14,17,17,14,17,17,14}, {14,17,17,15,1,1,14}
};
static const uint8_t colon_glyph[7] = {0,4,4,0,4,4,0};

static void draw_score(void) {
    uint8_t digits[10], count = 0, d, row, col, limit;
    uint32_t value = score;
    do { digits[count++] = (uint8_t)(value % 10u); value /= 10u; } while (value && count < 10);
    limit=count>displayed_count?count:displayed_count;
    for (d = 0; d < limit; ++d) {
        uint8_t x = (uint8_t)(75u-d*6u), glyph=d<count?digits[d]:10;
        if(d<displayed_count && displayed_digits[d]==glyph)continue;
        for(row=0;row<7;row++){
            uint8_t bits=glyph<10?score_digits[glyph][row]:0;
            vram_at((uint32_t)(55u+row)*320u+x);
            for(col=0;col<6;col++){
                uint8_t background=score_backup[(uint16_t)(5u+row)*77u+x-7u+col];
                VERA.data0=col<5 && (bits&(16u>>col))?10:background;
            }
        }
        displayed_digits[d]=glyph;
    }
    displayed_count=count;
}

static void draw_time(void) {
    uint8_t chars[4], ch, row, col, px, py;
    chars[0] = (uint8_t)(time_left / 60u);
    chars[1] = 10;
    chars[2] = (uint8_t)((time_left % 60u) / 10u);
    chars[3] = (uint8_t)(time_left % 10u);
    for(ch=0;ch<4;ch++){
        if(time_display_valid && displayed_time[ch]==chars[ch])continue;
        for(row=0;row<7;row++)for(py=0;py<2;py++){
            uint8_t bits=ch==1?colon_glyph[row]:score_digits[chars[ch]][row];
            vram_at((uint32_t)(98u+row*2u+py)*320u+31u+ch*12u);
            for(col=0;col<6;col++)for(px=0;px<2;px++){
                uint8_t background=time_backup[(uint16_t)(row*2u+py)*48u+ch*12u+col*2u+px];
                VERA.data0=col<5 && (bits&(16u>>col))?10:background;
            }
        }
        displayed_time[ch]=chars[ch];
    }
    time_display_valid=1;
}

static void timer_frame(void) {
    /* The PCM stream is the only real-time reference: a frame that overran its
     * VSYNC still drained (and got repaid) a full frame's samples.  Counting
     * loop iterations made a 1.5-frame cascade tick 1.5x too slowly. */
    uint8_t ticks = music_frames_elapsed();
    if (!timer_active || GAME_MODE || game_over) return;
    time_frames += ticks;
    if (time_frames < 60u) return;
    while (time_frames >= 60u) {        /* keep the sub-second remainder */
        time_frames -= 60u;
        if (time_left) --time_left;
    }
    draw_time();
    if (!time_left) {
        game_over = 1;
        timer_active = 0;
        if (!resolving) show_game_over();
    }
}

static void palette(void) {
    /* Generated RGB444 palette reserves 10 cyan, 11 white, 12 black ink. */
    uint16_t i;
    vram_at(0x1FA00u);
    for (i = 0; i < sizeof(game_palette); ++i) VERA.data0 = game_palette[i];
    vram_at(0x1FA14u); VERA.data0 = 0xFF; VERA.data0 = 0x00; /* unused index 10: cursor cyan */
    vram_at(0x1FA16u); VERA.data0 = 0xFF; VERA.data0 = 0x0F; /* index 11: game-over white */
}

static uint8_t *const disk_path = (uint8_t *)0x0B00;
static uint8_t disk_ref, disk_open;
static uint8_t disk_epoch_value;
static uint32_t disk_size;

/* Music keeps MUSIC.PCM open across the game, but any other OPEN closes it.
 * The generation counter lets music_tick notice and reopen before reading. */
uint8_t disk_epoch(void) { return disk_epoch_value; }

static void disk_close_file(void) {
    if (!disk_open) return;
    mli_close_params[1] = disk_ref;
    mli_close();
    disk_open = 0;
}
void disk_close(void) { disk_close_file(); }

uint8_t disk_file(const char *name, uint8_t len, uint16_t *key, uint32_t *size) {
    uint8_t i, n;
    uintptr_t p;
    disk_close_file();
    p = (uintptr_t)disk_path;
    mli_prefix_params[1] = (uint8_t)p;
    mli_prefix_params[2] = (uint8_t)(p >> 8);
    mli_get_prefix();
    if (mli_status || disk_path[0] > 63) return 0;
    n = disk_path[0];
    if (n && disk_path[n] != '/') {
        if (n >= 63) return 0;
        disk_path[++n] = '/';
    }
    for (i = 0; i < len; ++i) {
        if (n >= 64) return 0;
        disk_path[++n] = (uint8_t)name[i];
    }
    disk_path[0] = n;
    p = (uintptr_t)disk_path;
    mli_open_params[1] = (uint8_t)p;
    mli_open_params[2] = (uint8_t)(p >> 8);
    mli_open_params[3] = 0x00;
    mli_open_params[4] = 0xB8;
    mli_open_params[5] = 0;
    mli_open();
    if (mli_status) return 0;
    disk_ref = mli_open_params[5];
    disk_open = 1;
    ++disk_epoch_value;
    mli_eof_params[1] = disk_ref;
    mli_get_eof();
    if (mli_status) { disk_close_file(); return 0; }
    disk_size = (uint32_t)mli_eof_params[2] | ((uint32_t)mli_eof_params[3] << 8)
        | ((uint32_t)mli_eof_params[4] << 16);
    *key = 0; /* disk_read now addresses 512-byte offsets within this open file. */
    *size = disk_size;
    return 1;
}

void disk_read(uint16_t block, uint8_t *dest) {
    uint32_t offset = (uint32_t)block << 9;
    uint16_t count;
    uintptr_t p;
    if (!disk_open || offset >= disk_size) { mli_status = 0x4C; return; }
    count = disk_size - offset > 512u ? 512u : (uint16_t)(disk_size - offset);
    mli_mark_params[1] = disk_ref;
    mli_mark_params[2] = (uint8_t)offset;
    mli_mark_params[3] = (uint8_t)(offset >> 8);
    mli_mark_params[4] = (uint8_t)(offset >> 16);
    mli_set_mark();
    if (mli_status) return;
    p = (uintptr_t)dest;
    mli_read_params[1] = disk_ref;
    mli_read_params[2] = (uint8_t)p;
    mli_read_params[3] = (uint8_t)(p >> 8);
    mli_read_params[4] = (uint8_t)count;
    mli_read_params[5] = (uint8_t)(count >> 8);
    mli_read_params[6] = mli_read_params[7] = 0;
    mli_read();
    if (mli_status == 0 && (mli_read_params[6] != (uint8_t)count
        || mli_read_params[7] != (uint8_t)(count >> 8))) mli_status = 0x4C;
}

/* Sequential READ: continues where the previous READ stopped.  The music
 * streamer SET_MARKs once per loop instead of once per 512-byte block.  The
 * transferred count is returned instead of forcing status $4C on a short
 * read: ProDOS is allowed to satisfy less than the request (and some versions
 * cap READ at one block), and the streamer just queues what came back. */
uint16_t disk_read_seq(uint16_t count, uint8_t *dest) {
    uintptr_t p;
    if (!disk_open) { mli_status = 0x4C; return 0; }
    p = (uintptr_t)dest;
    mli_read_params[1] = disk_ref;
    mli_read_params[2] = (uint8_t)p;
    mli_read_params[3] = (uint8_t)(p >> 8);
    mli_read_params[4] = (uint8_t)count;
    mli_read_params[5] = (uint8_t)(count >> 8);
    mli_read_params[6] = mli_read_params[7] = 0;
    mli_read();
    if (mli_status) return 0;
    return (uint16_t)mli_read_params[6] | ((uint16_t)mli_read_params[7] << 8);
}

static void upload_scene(void) {
    /* $B800 is the ProDOS OPEN I/O buffer; payload data uses the separate
       staging page shared with startup audio loading. */
    uint8_t *buf = (uint8_t *)0x0C00;
    uint32_t size, done = 0;
    uint16_t block = 0;
    uint8_t want_count = 1, count = 0, first = 1, raw = 0;
    if (!disk_file(GAME_MODE ? "ENDLESS.RLE" : "GAME.RLE", GAME_MODE ? 11u : 8u, &block, &size)) return;
    vram_at(0);
    while (done < size) {
        uint16_t n = size - done > 512u ? 512u : (uint16_t)(size - done);
        uint16_t p;
        disk_read(block++, buf); if (mli_status) return;
        for (p = 0; p < n; ++p) {
            uint8_t b = buf[p], q;
            if (raw) VERA.data0 = b;
            else if (want_count) { count = b; want_count = 0; }
            else {
                if (first && !count && !b) raw = 1;
                else for (q = 0; q < count; ++q) VERA.data0 = b;
                first = 0; want_count = 1;
            }
        }
        done += n;
        loading_step();
    }
}

/* The original grid is 26 pixels apart.  Hardware sprites let the 24-pixel
 * art sit on that exact pitch; forcing it into 8-pixel tiles was the source
 * of the accumulating checkerboard offset. */
static void put_sprite(uint8_t slot, uint16_t pattern, uint16_t x, uint16_t y) {
    uint32_t full = SPRITE_PATTERNS + pattern;
    vram_at(0x1FC00u + (uint32_t)slot * 8u);
    VERA.data0 = (uint8_t)(full >> 5);
    VERA.data0 = (uint8_t)((full >> 13) | 0x80u); /* 8bpp */
    VERA.data0 = (uint8_t)x; VERA.data0 = (uint8_t)(x >> 8);
    VERA.data0 = (uint8_t)y; VERA.data0 = (uint8_t)(y >> 8);
    VERA.data0 = 0x08;                         /* z-depth 2: overlays above gems */
    VERA.data0 = 0xA0;                         /* 32 x 32 */
}

static void hide_sprite(uint8_t slot) {
    vram_at(0x1FC06u + (uint32_t)slot * 8u);
    VERA.data0 = 0;
}

static void move_sprite(uint8_t slot, uint16_t x, uint16_t y) {
    vram_at(0x1FC02u+(uint16_t)slot*8u);
    VERA.data0=(uint8_t)x;VERA.data0=(uint8_t)(x>>8);
    VERA.data0=(uint8_t)y;VERA.data0=(uint8_t)(y>>8);
}

static void move_sprite_y(uint8_t slot,uint16_t y) {
    VERA.control=0;VERA.address_hi=0x11;
    VERA.address=(uint16_t)(0xFC04u+((uint16_t)slot<<3));
    VERA.data0=(uint8_t)y;VERA.data0=(uint8_t)(y>>8);
}

static void draw_gem(uint8_t x, uint8_t y, uint8_t gem) {
    put_sprite((uint8_t)(y * 8u + x), (uint16_t)((gem - 1u) * 1024u), GEM_X(x), GEM_Y(y));
}

static void draw_gems(void) {
    uint8_t x, y;
    for (y = 0; y < 8; ++y) for (x = 0; x < 8; ++x) draw_gem(x, y, board.cells[y][x]);
}

static void set_cursor_sprite(void) {
    effects_cursor(cursor_x, cursor_y, selected, select_x, select_y);
}

static void animate_swap(uint8_t ax, uint8_t ay, uint8_t bx, uint8_t by) {
    uint8_t i, aslot = (uint8_t)(ay * 8u + ax), bslot = (uint8_t)(by * 8u + bx);
    int16_t dx = (int16_t)GEM_X(bx) - GEM_X(ax);
    int16_t dy = (int16_t)GEM_Y(by) - GEM_Y(ay);
    for (i = 1; i <= 8; ++i) {
        move_sprite(aslot,
                   (uint16_t)((int16_t)GEM_X(ax) + dx * i / 8),
                   (uint16_t)((int16_t)GEM_Y(ay) + dy * i / 8));
        move_sprite(bslot,
                   (uint16_t)((int16_t)GEM_X(bx) - dx * i / 8),
                   (uint16_t)((int16_t)GEM_Y(by) - dy * i / 8));
        waitvsync();
    }
}

/* Keep the visible sprites independent from the logical matrix while a
 * cascade resolves. Surviving gems retain their old artwork and physically
 * travel to their compressed row; replacement gems enter from above. */
static void animate_fall(const Board *before, const uint8_t marks[8][8]) {
    uint8_t x, y, out, i, slot, active;
    /* Easing offsets indexed by whole rows fallen and animation frame. */
    static const uint8_t displacement[9][16] = {
        {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        {0, 0, 0, 0, 1, 2, 3, 4, 6, 8, 10, 12, 14, 17, 19, 22},
        {0, 0, 0, 1, 3, 5, 7, 9, 13, 16, 20, 24, 29, 34, 39, 45},
        {0, 0, 1, 2, 4, 7, 10, 14, 19, 24, 30, 36, 43, 51, 59, 68},
        {0, 0, 1, 3, 6, 10, 14, 19, 26, 32, 40, 49, 58, 68, 79, 91},
        {0, 0, 2, 4, 8, 12, 18, 24, 32, 41, 50, 61, 73, 85, 99, 114},
        {0, 0, 2, 5, 9, 15, 21, 29, 39, 49, 60, 73, 87, 102, 119, 137},
        {0, 0, 2, 6, 11, 17, 25, 34, 45, 57, 71, 86, 102, 120, 139, 159},
        {0, 0, 3, 7, 13, 20, 29, 39, 52, 65, 81, 98, 117, 137, 159, 182}
    };
    for (slot = 0; slot < 64; ++slot) fall_gem[slot] = 0;
    for (x = 0; x < 8; ++x) {
        active = 0;
        for (y = 0; y < 8; ++y) if (marks[y][x]) { active = 1; break; }
        if (!active) continue;
        out = 7;
        for (y = 8; y--;) if (!marks[y][x]) {
            slot = (uint8_t)(out * 8u + x);
            if(out != y) {
                fall_gem[slot] = before->cells[y][x]; fall_sy[slot] = (int16_t)GEM_Y(y); fall_dy[slot] = GEM_Y(out);
                fall_rows[slot] = (uint8_t)(out - y);
            }
            --out;
        }
        active = (uint8_t)(out + 1u);
        while ((int8_t)out >= 0) {
            slot = (uint8_t)(out * 8u + x);
            fall_gem[slot] = board.cells[out][x];
            fall_sy[slot] = (int16_t)GEM_Y(out) - (int16_t)(active * 26u);
            fall_rows[slot] = active;
            fall_dy[slot] = GEM_Y(out); --out;
        }
    }
    /* Populate destinations bottom-up: a survivor's destination is prepared
     * before its old slot is reused by a gem entering from above. */
    for(slot=64;slot--;)if(fall_gem[slot])
        put_sprite(slot,(uint16_t)((fall_gem[slot]-1u)*1024u),GEM_X(slot&7u),(uint16_t)fall_sy[slot]);
    for (i = 1; i <= 16; ++i) {
        for (slot = 0; slot < 64; ++slot) if (fall_gem[slot])
            move_sprite_y(slot, i == 16 ? fall_dy[slot] :
                          (uint16_t)(fall_sy[slot] + displacement[fall_rows[slot]][i]));
        waitvsync();
    }
    sound_play(SFX_FALL);
}

static uint8_t letter_row(uint8_t ch, uint8_t row) {
    static const uint8_t a[7]={14,17,17,31,17,17,17}, c[7]={14,17,16,16,16,17,14};
    static const uint8_t e[7]={31,16,16,30,16,16,31}, g[7]={14,17,16,23,17,17,15};
    static const uint8_t h[7]={17,17,17,31,17,17,17}, i[7]={31,4,4,4,4,4,31};
    static const uint8_t l[7]={16,16,16,16,16,16,31}, m[7]={17,27,21,21,17,17,17};
    static const uint8_t o[7]={14,17,17,17,17,17,14}, r[7]={30,17,17,30,20,18,17};
    static const uint8_t s[7]={15,16,16,14,1,1,30}, t[7]={31,4,4,4,4,4,4};
    static const uint8_t v[7]={17,17,17,17,17,10,4};
    switch (ch) {
        case 'A': return a[row]; case 'C': return c[row]; case 'E': return e[row];
        case 'G': return g[row]; case 'H': return h[row]; case 'I': return i[row];
        case 'L': return l[row]; case 'M': return m[row]; case 'O': return o[row];
        case 'R': return r[row]; case 'S': return s[row]; case 'T': return t[row];
        case 'V': return v[row]; case ':': return colon_glyph[row];
        default: return 0;
    }
}

static void draw_char(uint8_t ch, uint16_t x, uint8_t y, uint8_t scale, uint8_t color) {
    uint8_t row, col, px, py, bits;
    for (row = 0; row < 7; ++row) {
        bits = (ch >= '0' && ch <= '9') ? score_digits[ch - '0'][row] : letter_row(ch, row);
        for (col = 0; col < 5; ++col) if (bits & (uint8_t)(16u >> col))
            for (py = 0; py < scale; ++py) for (px = 0; px < scale; ++px) {
                vram_at((uint32_t)(y + row * scale + py) * 320u + x + col * scale + px);
                VERA.data0 = color;
            }
    }
}

static void draw_centered(const char *text, uint8_t y, uint8_t scale, uint8_t color) {
    uint8_t len = 0, n;
    uint16_t x;
    while (text[len]) ++len;
    x = (uint16_t)(200u - ((uint16_t)len * 6u * scale - scale) / 2u);
    for (n = 0; n < len; ++n) draw_char((uint8_t)text[n], (uint16_t)(x + (uint16_t)n * 6u * scale), y, scale, color);
}

static void drop_all_gems(void) {
    uint8_t frame, slot;
    static const uint8_t progress[50]={0,0,0,1,2,3,5,6,8,10,12,14,17,20,23,26,29,33,36,40,45,49,54,58,64,69,74,80,86,92,98,104,111,118,125,132,140,147,155,163,172,180,189,198,207,216,226,235,245,255};
    effects_clear();
    hide_sprite(EFFECT_CURSOR_SLOT); hide_sprite(EFFECT_SELECTION_SLOT);
    for(slot=0;slot<64;slot++){
        uint8_t x=slot&7u,y=slot>>3;
        fall_sy[slot]=(int16_t)GEM_Y(y);
        /* Every displacement is a multiple of 26. Halve first so the
         * eased product fits uint16, avoiding 64 long multiplies/frame. */
        fall_dy[slot]=(uint16_t)((GEM_Y((uint8_t)(9u+((x*3u+y*5u)&7u)))-GEM_Y(y))>>1);
    }
    for (frame = 1; frame <= 50; ++frame) {
        for (slot = 0; slot < 64; ++slot) {
            uint16_t pos=(uint16_t)fall_sy[slot]+(frame==50 ? fall_dy[slot]*2u :
                (uint16_t)((fall_dy[slot]*progress[frame-1u])>>7));
            move_sprite_y(slot,pos);
        }
        /* The original 50-step ease-in is slower than a 60 Hz pass. Update
         * motion at 30 Hz while VERA continues presenting every frame. */
        waitvsync();
        waitvsync();
    }
    for (slot = 0; slot < 64; ++slot) hide_sprite(slot);
}


static void show_game_over(void) {
    uint8_t digits[10], count = 0, n;
    uint32_t value;
    drop_all_gems();
    if (score > high_score) { high_score = score; HISCORE_DIRTY = 1; }
    draw_centered("GAME OVER", 58, 3, 0);
    draw_centered("GAME OVER", 57, 3, 11);
    value = score;
    do { digits[count++] = (uint8_t)(value % 10u); value /= 10u; } while (value && count < 10);
    for (n = 0; n < count; ++n)
        draw_char((uint8_t)('0' + digits[count - 1u - n]),
                  (uint16_t)(200u - ((uint16_t)count * 18u - 3u) / 2u + (uint16_t)n * 18u), 88, 3, 11);
    value = high_score; count = 0;
    do { digits[count++] = (uint8_t)(value % 10u); value /= 10u; } while (value && count < 10);
    {
        static const char label[] = "LATEST HIGH SCORE:";
        uint16_t x = (uint16_t)(200u - ((uint16_t)(18u + count) * 6u - 1u) / 2u);
        for (n = 0; n < 18; ++n) draw_char((uint8_t)label[n], (uint16_t)(x + (uint16_t)n * 6u), 119, 1, 11);
        for (n = 0; n < count; ++n)
            draw_char((uint8_t)('0' + digits[count - 1u - n]),
                      (uint16_t)(x + (uint16_t)(18u + n) * 6u), 119, 1, 11);
    }
}

static void upload_gems(void) {
    uint8_t *buf=(uint8_t *)0x0C00,n;
    uint16_t i,key;uint32_t size;
    if(!disk_file("GEM.PAT",7,&key,&size)||size!=7168u)return;
    vram_at(SPRITE_PATTERNS);
    for(n=0;n<14;n++){
        disk_read(n,buf);if(mli_status)return;
        loading_step();
        for(i=0;i<512;i++)VERA.data0=buf[i];
    }
}

static void redraw_game(void) {
    uint8_t slot, x, y;
    uint8_t marks[8][8];
    /* Hide effect/cursor slots above the gem grid */
    for (slot = 64; slot < 128; ++slot) hide_sprite(slot);
    /* Place all gem sprites above the visible area so animate_fall drops them
     * in Ã¢â‚¬â€ matching the original game's reset behaviour. */
    for (y = 0; y < 8; ++y)
        for (x = 0; x < 8; ++x)
            put_sprite((uint8_t)(y * 8u + x),
                       (uint16_t)((board.cells[y][x] - 1u) * 1024u),
                       GEM_X(x),
                       (uint16_t)(GEM_Y(0) - (uint16_t)(8u - y) * 26u));
    /* marks=all 1 Ã¢â€ â€™ every gem is treated as "new" and falls from above */
    for (y = 0; y < 8; ++y) for (x = 0; x < 8; ++x) marks[y][x] = 1;
    animate_fall(&board, marks);
    set_cursor_sprite();
}

static void move_cursor(int8_t dx, int8_t dy) {
    int8_t x = (int8_t)cursor_x + dx, y = (int8_t)cursor_y + dy;
    if (x < 0) x = 7; else if (x > 7) x = 0;
    if (y < 0) y = 7; else if (y > 7) y = 0;
    cursor_x = (uint8_t)x; cursor_y = (uint8_t)y;
    set_cursor_sprite();
    sound_play(SFX_SELECT);
}

static __attribute__((noinline)) void check_no_moves(void) {
    uint8_t marks[8][8],x,y;
    if(board_has_solution(&board))return;
    if(GAME_MODE){
        game_over=1;timer_active=0;
        show_game_over();
    }else{
        /* Original Time Trial: drop the dead board and deal a new one,
           retaining score and the running countdown. */
        resolving=1;
        drop_all_gems();
        if(!game_over){
            before_fall=board;
            board_generate(&board);
            for(y=0;y<8;y++)for(x=0;x<8;x++)marks[y][x]=1;
            animate_fall(&before_fall,marks);
        }
        resolving=0;
        if(game_over)show_game_over();
        else set_cursor_sprite();
    }
}

static void select_gem(void) {
    uint8_t marks[8][8], t, cascade = 0, x, y, frame;
    if (!selected) { selected = 1; select_x = cursor_x; select_y = cursor_y; set_cursor_sprite(); sound_play(SFX_SELECT); return; }
    if (board_swap_creates_match(&board, select_x, select_y, cursor_x, cursor_y)) {
        resolving = 1;
        sound_play(SFX_SELECT);
        effects_hide_hint();
        hide_sprite(EFFECT_CURSOR_SLOT); hide_sprite(EFFECT_SELECTION_SLOT);
        animate_swap(select_x, select_y, cursor_x, cursor_y);
        t = board.cells[select_y][select_x];
        board.cells[select_y][select_x] = board.cells[cursor_y][cursor_x];
        board.cells[cursor_y][cursor_x] = t;
        draw_gem(select_x, select_y, board.cells[select_y][select_x]);
        draw_gem(cursor_x, cursor_y, board.cells[cursor_y][cursor_x]);
        while (board_mark_matches(&board, marks)) {
            before_fall = board;
            ++cascade;
            sound_play(cascade == 1 ? SFX_MATCH1 : cascade == 2 ? SFX_MATCH2 : SFX_MATCH3);
            effects_matches(&board, marks, (uint8_t)((cascade == 1u && hint_used) ? 0u : 5u), cascade);
            score += (uint32_t)board_score_matches(&board) *
                     (uint32_t)((cascade == 1u && hint_used) ? 0u : 5u) * cascade;
            draw_score();
            if (score > high_score) { high_score = score; HISCORE_DIRTY = 1; }
            /* Brief sparkle/reveal, then fall. No bitmap erasure or commit. */
            for(y=0;y<8;y++)for(x=0;x<8;x++)if(marks[y][x])hide_sprite((uint8_t)(y*8u+x));
            for(frame=0;frame<6;frame++)waitvsync();
            board_clear_and_refill(&board, marks);
            animate_fall(&before_fall, marks);
            hint_used = 0;
        }
    } else if (select_x != cursor_x || select_y != cursor_y) sound_play(SFX_SELECT);
    else sound_play(SFX_SELECT);
    selected = 0;
    /* Gems remain at their final sprite positions; only restore cursor. */
    set_cursor_sprite();
    resolving = 0;
    if (game_over) show_game_over();
    else {
        move_check_frames = 0;
        check_no_moves();
    }
}

static void handle_key(uint8_t key) {
    if (game_over && key != 'R' && key != 0x1B) return;
    if (key == 0x08) move_cursor(-1, 0);
    else if (key == 0x15) move_cursor(1, 0);
    else if (key == 0x0B) move_cursor(0, -1);
    else if (key == 0x0A) move_cursor(0, 1);
    else if (key == 0x20) select_gem();
    else if (key == 'H') {
        uint8_t x, y, dx, dy;
        if (board_find_solution(&board, &x, &y, &dx, &dy)) {
            hint_used = 1;
            effects_hint(x,y);
        }
    } else if (key == 'R') {
        uint8_t i;
        sound_stop();
        music_stop();music_restart();
        /* Erase game-over text directly in VRAM Ã¢â‚¬â€ much faster than reloading
           the entire scene from disk, and gives the same instant-clear look
           that the original game had before gems start falling. */
        if(game_over)upload_scene();
        effects_clear();
        selected = 0; hint_used = 0; score = 0; game_over = 0; resolving = 0;
        time_left = 120; time_frames = 0; timer_active = 1;
        /* Invalidate HUD caches so all digits and the timer colon are
           repainted even when their values happen to be unchanged. */
        displayed_count = 10;
        for (i = 0; i < 10; ++i) displayed_digits[i] = 0xFF;
        time_display_valid = 0;
        draw_score();
        if (!GAME_MODE) draw_time();
        board_generate(&board); redraw_game(); move_check_frames = 29;
    } else if (key == 0x1B) {
        sound_stop();
        music_stop();
        /* Release the final open ProDOS file before the resident loader
           opens its marker and score files with the same I/O buffer. */
        disk_close();
        NEXT_IMAGE = 0; ((void (*)(void))0x2000)();
    }
}

/* Mouse coordinates use the same 26px cells as the hardware gem sprites.
 * A rising primary-button edge has the same meaning as Space: select/swap. */
static void mouse_update(void) {
    uint16_t x;
    uint8_t y, down, moved, pressed;
    if (!mouse_slot) return;
    mouse_poll();
    x=mouse_x; y=mouse_y;
    down=(mouse_buttons&0x80u)!=0;
    moved=x!=mouse_last_x || y!=mouse_last_y;
    pressed=down && !mouse_was_down;
    if(!down)mouse_drag=0;
    mouse_last_x=x;mouse_last_y=y;mouse_was_down=down;
    effects_mouse(x,y);
    if(pressed && x>=7u && x<85u){
        if(y>=168u && y<185u)handle_key('H');
        else if(y>=187u && y<204u)handle_key('R');
        else if(y>=215u && y<232u)handle_key(0x1B);
        effects_mouse(x,y);
        return;
    }
    if (app_mode && !game_over && !resolving && (moved || pressed) &&
        x>=93u && x<301u && y>=13u && y<221u) {
        uint8_t cx=(uint8_t)((x-93u)/26u);
        uint8_t cy=(uint8_t)((y-13u)/26u);
        if(cx!=cursor_x || cy!=cursor_y) {
            cursor_x=cx;cursor_y=cy;
            set_cursor_sprite();
        }
        if(pressed){select_gem();mouse_drag=selected;}
        else if(down && mouse_drag && selected){
            uint8_t dx=(uint8_t)(cx-select_x),dy=(uint8_t)(cy-select_y);
            if((!dx && (dy==1u || dy==255u)) || (!dy && (dx==1u || dx==255u))){
                mouse_drag=0;select_gem();
            }
        }
    }
}

static void vera_init(void) {
    VERA.control = 0;
    VERA.display.video = 0;
    VERA.display.border = 0;
    VERA.display.hscale = 0x40;
    VERA.display.vscale = 0x40;
    VERA.layer0.config = 0;
    VERA.layer1.config = 0;
}

static void start_game(void) {
    uint8_t slot;
    /* Finish startup disk I/O before initializing gameplay and effects. The
       MLI bridge additionally preserves compiler ZP state. */
    loading_stage("SCENE");upload_scene();
    loading_stage("MUSIC");
    music_init();
    loading_stage("SOUND EFFECTS");
    sound_init();
    loading_stage("PREPARING BOARD");
    effects_init();
    header_mask();
    board_seed(&board, RANDOM_SEED);
    board_generate(&board);
    move_check_frames = 29;
    RANDOM_SEED=board.rng;
    cursor_x = 3; cursor_y = 3; selected = 0; hint_used = 0; score = 0;
    time_left = 120; time_frames = 0; timer_active = 0; game_over = 0; resolving = 0;
    backup_score_panel();
    backup_time_digits();
    draw_score();
    if (!GAME_MODE) draw_time();
    for (slot = 0; slot < 128; ++slot) hide_sprite(slot);
    draw_gems();
    set_cursor_sprite();
    timer_active = 1;
    app_mode = 1;
    /* GAME_MODE is set by title: 0=Time Trial, 1=Endless.  The board path is
       shared; the timed HUD is updated in the next gameplay pass. */
    (void)GAME_MODE;
}

int main(void) {
    loading_active=1;loading_done=0;loading_percent=0;
    loading_total=GAME_MODE?LOADING_ENDLESS_BLOCKS:LOADING_TIMED_BLOCKS;
    loading_draw(0);loading_stage("GEMS");
    vera_init();
    palette();
    (void)mouse_init();
    VERA.layer0.config = 0x07; /* 320x240 8bpp bitmap at VRAM $00000 */
    VERA.layer0.mapbase = 0;
    VERA.layer0.tilebase = 0;
    VERA.layer0.hscroll = 0; VERA.layer0.vscroll = 0;
    upload_gems();
    start_game();
    loading_draw(100);loading_stage("GAME START");loading_active=0;
    VERA.display.video = 0x71;
    for (;;) {
        waitvsync();
        mouse_update();
        if (app_mode && !resolving && !game_over) {
            /* Also check the idle board, independently of keys or dirty flags.
               A half-second interval keeps full dead-board scans off the
               cursor animation path on a 1 MHz Apple II. */
            if (++move_check_frames >= 30) {
                move_check_frames = 0;
                check_no_moves();
            }
        }
        if (kbd_pressed()) {
            uint8_t key = kbd_read(); kbd_clear();
            if (app_mode) handle_key(key);
        }
    }
    return 0;
}

