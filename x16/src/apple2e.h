// Commander X16 port of the VERA Freegemas hardware layer.
// VERA is memory-mapped at $9F20; input and file I/O go through the KERNAL.

#ifndef _APPLE2E_H
#define _APPLE2E_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VERA_BASE 0x9F20

struct __vera {
    unsigned short      address;
    unsigned char       address_hi;
    unsigned char       data0;
    unsigned char       data1;
    unsigned char       control;
    unsigned char       irq_enable;
    unsigned char       irq_flags;
    unsigned char       irq_raster;
    union {
        struct {
            unsigned char video;
            unsigned char hscale;
            unsigned char vscale;
            unsigned char border;
        };
        struct {
            unsigned char hstart;
            unsigned char hstop;
            unsigned char vstart;
            unsigned char vstop;
        };
        struct {
            unsigned char fxctrl;
            unsigned char fxtilebase;
            unsigned char fxmapbase;
            unsigned char fxmult;
        };
        struct {
            unsigned char fxxincrl;
            unsigned char fxxincrh;
            unsigned char fxyincrl;
            unsigned char fxyincrh;
        };
        struct {
            unsigned char fxxposl;
            unsigned char fxxposh;
            unsigned char fxyposl;
            unsigned char fxyposh;
        };
        struct {
            unsigned char fxxposs;
            unsigned char fxyposs;
            unsigned char fxpolyfilll;
            unsigned char fxpolyfillh;
        };
        struct {
            unsigned char fxcachel;
            unsigned char fxcachem;
            unsigned char fxcacheh;
            unsigned char fxcacheu;
        };
        struct {
            unsigned char dcver0;
            unsigned char dcver1;
            unsigned char dcver2;
            unsigned char dcver3;
        };
    } display;
    struct {
        unsigned char   config;
        unsigned char   mapbase;
        unsigned char   tilebase;
        unsigned int    hscroll;
        unsigned int    vscroll;
    } layer0;
    struct {
        unsigned char   config;
        unsigned char   mapbase;
        unsigned char   tilebase;
        unsigned int    hscroll;
        unsigned int    vscroll;
    } layer1;
    struct {
        unsigned char   control;
        unsigned char   rate;
        unsigned char   data;
    } audio;
    struct {
        unsigned char   data;
        unsigned char   control;
    } spi;
};

#define VERA    (*(volatile struct __vera *)VERA_BASE)

#define VERA_INC_0    ((0 << 1) | 0) << 3
#define VERA_INC_1    ((1 << 1) | 0) << 3
#define VERA_INC_2    ((2 << 1) | 0) << 3
#define VERA_INC_4    ((3 << 1) | 0) << 3
#define VERA_INC_8    ((4 << 1) | 0) << 3
#define VERA_INC_16   ((5 << 1) | 0) << 3
#define VERA_INC_32   ((6 << 1) | 0) << 3
#define VERA_INC_64   ((7 << 1) | 0) << 3
#define VERA_INC_128  ((8 << 1) | 0) << 3
#define VERA_INC_256  ((9 << 1) | 0) << 3
#define VERA_INC_512  ((10 << 1) | 0) << 3
#define VERA_INC_40   ((11 << 1) | 0) << 3
#define VERA_INC_80   ((12 << 1) | 0) << 3
#define VERA_INC_160  ((13 << 1) | 0) << 3
#define VERA_INC_320  ((14 << 1) | 0) << 3
#define VERA_INC_640  ((15 << 1) | 0) << 3

#define VERA_INC_BANK0  (VERA_INC_1)
#define VERA_INC_BANK1  (VERA_INC_1 | 1)

static inline void vera_set_addr(uint8_t inc, uint16_t addr) {
    VERA.address_hi = inc;
    VERA.address = addr;
}

#define VERA_IRQ_VSYNC       0x01
#define VERA_IRQ_RASTER      0x02
#define VERA_IRQ_SPR_COLL    0x04
#define VERA_IRQ_AUDIO_LOW   0x08

/* Shared state survives $3000 overlay reloads.  Fixed RAM top page:
 *   $9E00..$9EFF  state, $9DFF down  stack, $9E00 top of overlay image.
 * The IRQ handler increments the byte at X16_FRAME (60 Hz VERA VSYNC). */
#define X16_STATE_BASE 0x9E00u
#define NEXT_IMAGE      (*(volatile uint8_t *)(X16_STATE_BASE + 0x00u))
#define GAME_MODE       (*(volatile uint8_t *)(X16_STATE_BASE + 0x01u))
#define MUSIC_SETTING   (*(volatile uint8_t *)(X16_STATE_BASE + 0x02u))
#define SOUND_SETTING   (*(volatile uint8_t *)(X16_STATE_BASE + 0x03u))
#define DETECTED_VERA   (*(volatile uint8_t *)(X16_STATE_BASE + 0x04u))
#define HISCORE_DIRTY   (*(volatile uint8_t *)(X16_STATE_BASE + 0x05u))
#define HISCORE_INIT    (*(volatile uint8_t *)(X16_STATE_BASE + 0x06u))
#define SETTINGS_INIT   (*(volatile uint8_t *)(X16_STATE_BASE + 0x07u))
#define RANDOM_SEED     (*(volatile uint16_t *)(X16_STATE_BASE + 0x08u))
#define HIGH_SCORES     ((volatile uint32_t *)(X16_STATE_BASE + 0x0Cu))
#define X16_FRAME       (*(volatile uint8_t *)(X16_STATE_BASE + 0x14u))
#define X16_IRQ_READY   (*(volatile uint8_t *)(X16_STATE_BASE + 0x15u))

/* Default banked-RAM bank holding the HUD background cache. */
#define X16_HUD_BANK 20u
#define score_backup ((uint8_t *)0xA000u)
#define time_backup  ((uint8_t *)0xA600u)

/* KERNAL file loader wrapper (x16_platform.s).  Set fields, call x16_kload(). */
extern uint8_t  x16_name[40];
extern uint8_t  x16_namelen;
extern uint8_t  x16_sa;
extern uint8_t  x16_mode;      /* 0=RAM, 2=VRAM bank 0, 3=VRAM bank 1 */
extern uint8_t  x16_bank;      /* RAM bank for mode 0 */
extern uint16_t x16_addr;
extern uint8_t  x16_err;       /* 0 on success */
extern uint16_t x16_end;
void x16_kload(void);
void x16_ksave(void);          /* BSAVE, headerless */
void x16_kgetin(void);         /* result in x16_key */
void x16_kputc(uint8_t c);     /* KERNAL CHROUT */
void x16_kcint(void);          /* KERNAL CINT: restore text mode */
void x16_kjoystick(void);      /* x16_joy0/1/2 */
void x16_enter_basic(void);
void x16_irq_install(void);
void x16_irq_remove(void);
extern uint8_t x16_key;
extern uint8_t x16_joy0, x16_joy1, x16_joy2;
extern uint16_t x16_save_start, x16_save_end;

/* Streamed 16-bit music (x16_platform.s): logical file 3, 267..268-byte
 * MACPTR runs from music.zcm after its 8-byte header. */
extern uint8_t  x16_pcm_err;
extern uint16_t x16_pcm_count;
extern uint16_t x16_pcm_got;
extern uint8_t  x16_pcm_status;
extern uint8_t *x16_pcm_dest;
uint8_t x16_pcm_open(void);
void x16_pcm_read(void);
void x16_pcm_close(void);

/* Polling input queue. */
uint8_t kbd_pressed(void);
uint8_t kbd_read(void);
void kbd_clear(void);

#ifdef __cplusplus
}
#endif

#endif /* _APPLE2E_H */
