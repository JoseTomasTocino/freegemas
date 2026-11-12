// Copyright 2026 Time-Pilot-IIvera
// Apple //e VERA (VidHD-style VERA expansion card) hardware definitions.
//
// This header provides a cx16.h-compatible VERA interface mapped to the
// Apple II VERA card at Slot 2 ($C200) or Slot 4 ($C400).

#ifndef _APPLE2E_H
#define _APPLE2E_H

#ifdef __cplusplus
extern "C" {
#endif

/* ---------------- Apple II hardware addresses ---------------- */
#define KBD_DATA    (*(volatile unsigned char *)0xC000)  /* bit 7 set if pressed */
#define KBD_STROBE  (*(volatile unsigned char *)0xC010)  /* write/read clears strobe */

/* ---------------- VERA on Apple II ---------------- */
/* VERA registers are mapped at the slot's ROM space.
 * Slot 2 -> $C200, Slot 4 -> $C400.  Default Slot 2. */
#ifndef VERA_BASE
#define VERA_BASE 0xC200
#endif

struct __vera {
    unsigned short      address;        /* ADDR_L (7:0), ADDR_M (15:8) */
    unsigned char       address_hi;     /* ADDR_H (19:16) + stride/decr */
    unsigned char       data0;          /* Data port 0 */
    unsigned char       data1;          /* Data port 1 */
    unsigned char       control;        /* Control register */
    unsigned char       irq_enable;     /* Interrupt enable bits */
    unsigned char       irq_flags;      /* Interrupt flags */
    unsigned char       irq_raster;     /* Line where IRQ will occur */
    union {
        struct {                        /* DCSEL = 0 */
            unsigned char video;        /* Flags to enable video layers */
            unsigned char hscale;       /* Horizontal scale factor */
            unsigned char vscale;       /* Vertical scale factor */
            unsigned char border;       /* Border color */
        };
        struct {                        /* DCSEL = 1 */
            unsigned char hstart;
            unsigned char hstop;
            unsigned char vstart;
            unsigned char vstop;
        };
        struct {                        /* DCSEL = 2 */
            unsigned char fxctrl;
            unsigned char fxtilebase;
            unsigned char fxmapbase;
            unsigned char fxmult;
        };
        struct {                        /* DCSEL = 3 */
            unsigned char fxxincrl;
            unsigned char fxxincrh;
            unsigned char fxyincrl;
            unsigned char fxyincrh;
        };
        struct {                        /* DCSEL = 4 */
            unsigned char fxxposl;
            unsigned char fxxposh;
            unsigned char fxyposl;
            unsigned char fxyposh;
        };
        struct {                        /* DCSEL = 5 */
            unsigned char fxxposs;
            unsigned char fxyposs;
            unsigned char fxpolyfilll;
            unsigned char fxpolyfillh;
        };
        struct {                        /* DCSEL = 6 */
            unsigned char fxcachel;
            unsigned char fxcachem;
            unsigned char fxcacheh;
            unsigned char fxcacheu;
        };
        struct {                        /* DCSEL = 63 */
            unsigned char dcver0;
            unsigned char dcver1;
            unsigned char dcver2;
            unsigned char dcver3;
        };
    } display;
    struct {
        unsigned char   config;         /* Layer map geometry */
        unsigned char   mapbase;        /* Map data address */
        unsigned char   tilebase;       /* Tile address and geometry */
        unsigned int    hscroll;        /* Smooth scroll horizontal */
        unsigned int    vscroll;        /* Smooth scroll vertical */
    } layer0;
    struct {
        unsigned char   config;
        unsigned char   mapbase;
        unsigned char   tilebase;
        unsigned int    hscroll;
        unsigned int    vscroll;
    } layer1;
    struct {
        unsigned char   control;        /* PCM format */
        unsigned char   rate;           /* Sample rate */
        unsigned char   data;           /* PCM output queue */
    } audio;                            /* PCM registers */
    struct {
        unsigned char   data;
        unsigned char   control;
    } spi;                              /* SD card interface */
};

#define VERA    (*(volatile struct __vera *)VERA_BASE)

/* YM2151 (OPM) FM daughterboard: device-select space next to VERA's window. */
#define FM_BASE         (0xC080 + ((VERA_BASE >> 8) & 0x0F) * 0x10)
#define VERA_YM_REG     (*(volatile unsigned char *)(FM_BASE + 0))
#define VERA_YM_DATA    (*(volatile unsigned char *)(FM_BASE + 1))
#define YM_KEY_REG      0x08

/* VERA address increment/decrement strides (ADDR_H bits 7:4). */
#define VERA_DEC_0    ((0 << 1) | 1) << 3
#define VERA_DEC_1    ((1 << 1) | 1) << 3
#define VERA_DEC_2    ((2 << 1) | 1) << 3
#define VERA_DEC_4    ((3 << 1) | 1) << 3
#define VERA_DEC_8    ((4 << 1) | 1) << 3
#define VERA_DEC_16   ((5 << 1) | 1) << 3
#define VERA_DEC_32   ((6 << 1) | 1) << 3
#define VERA_DEC_64   ((7 << 1) | 1) << 3
#define VERA_DEC_128  ((8 << 1) | 1) << 3
#define VERA_DEC_256  ((9 << 1) | 1) << 3
#define VERA_DEC_512  ((10 << 1) | 1) << 3
#define VERA_DEC_40   ((11 << 1) | 1) << 3
#define VERA_DEC_80   ((12 << 1) | 1) << 3
#define VERA_DEC_160  ((13 << 1) | 1) << 3
#define VERA_DEC_320  ((14 << 1) | 1) << 3
#define VERA_DEC_640  ((15 << 1) | 1) << 3
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

/* VERA IRQ flags. */
#define VERA_IRQ_VSYNC       0x01
#define VERA_IRQ_RASTER      0x02
#define VERA_IRQ_SPR_COLL    0x04
#define VERA_IRQ_AUDIO_LOW   0x08

/* VERA VRAM layout used by Time Pilot. */
#define VERA_SPRITES_BASE   0xFC00
#define VERA_LAYER0         0x0000
#define VERA_LAYER1         0xB000
#define VERA_COLOR_PALETTE  0xFA00

/* ---------------- Keyboard helpers ---------------- */
static inline int kbd_pressed(void) {
    return (KBD_DATA & 0x80) != 0;
}

static inline unsigned char kbd_read(void) {
    return KBD_DATA & 0x7F;
}

static inline void kbd_clear(void) {
    (void)KBD_STROBE;  /* read clears strobe */
}

#ifdef __cplusplus
}
#endif

#endif /* _APPLE2E_H */
