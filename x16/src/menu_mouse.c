#include <stdint.h>
#include <cx16.h>
#include "menu_mouse.h"
#include "mouse_hand.h"

extern void x16_mouse_offset(void);

/* Commander X16 KERNAL mouse.  The pointer itself stays hidden: the game
 * paints its own 16x16 cursor sprite so the pointer can live in the same
 * sprite layer as the gems. */
volatile uint16_t mouse_x;
volatile uint8_t mouse_y;
volatile uint8_t mouse_buttons;
volatile uint8_t mouse_slot;

static mouse_pos_t pos;
static uint8_t prev_button;

#define MENU_CURSOR_VRAM 0x1FF00u
#define MENU_CURSOR_SLOT 127u
static void at(uint32_t a){VERA.control=0;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;}

static void draw_menu_cursor(void) {
    uint32_t p = MENU_CURSOR_VRAM;
    at(0x1FC00u + MENU_CURSOR_SLOT * 8u);
    VERA.data0 = (uint8_t)(p >> 5);
    VERA.data0 = (uint8_t)(p >> 13);
    VERA.data0 = (uint8_t)mouse_x;
    VERA.data0 = (uint8_t)(mouse_x >> 8);
    VERA.data0 = mouse_y;
    VERA.data0 = 0;
    VERA.data0 = 0x0C;  /* 16x16, 4bpp */
    VERA.data0 = 0x5F;  /* 16x16, palette offset 15: private hand colours */
}

static void upload_menu_cursor(void) {
    uint8_t i;
    at(MENU_CURSOR_VRAM);
    for (i = 0; i < (uint8_t)sizeof(mouse_hand); ++i) {
        VERA.data0 = mouse_hand[i];  /* keep 11 = white, 12 = black */
    }
}

static void poll_raw(void) {
    unsigned char buttons;
    int x, y;

    /* The KERNAL's default IRQ already runs mouse_scan.  Calling it again
       here can steal packets from the IRQ and adds nothing. */
    buttons = cx16_k_mouse_get(&pos);
    x = pos.x;
    y = pos.y;
    if (x < 0) x = 0;
    if (x > 319) x = 319;
    if (y < 0) y = 0;
    if (y > 239) y = 239;
    mouse_x = (uint16_t)x;
    mouse_y = (uint8_t)y;
    /* KERNAL reports buttons as bit0=left, bit1=right, bit2=middle.
       The shared game code treats bit7 as the primary button. */
    mouse_buttons = (uint8_t)((buttons & 1u) ? 0x80u : 0u);
}

uint8_t mouse_init(void) {
    /* A=$FF means "mouse on, do not draw the KERNAL cursor".  A=0 is not a
       hidden pointer: the ROM also turns msepar off and switches the SMC to
       keyboard-only packets, so mouse_scan/mouse_get then never move.  The
       game paints its own cursor sprite instead.  40x30 8-pixel cells
       declares a 320x240 range and centres the initial position. */
    cx16_k_mouse_config(0xFF, 40, 30);
    poll_raw();
    prev_button = (uint8_t)(mouse_buttons != 0);
    mouse_slot = 1;
    /* sprite_set_position turns sprite 0 back on (zdepth 3) on every mouse
       scan, so hiding attr6 is not enough.  Move the KERNAL sprite below the
       240-line screen instead; mouse_get still reports the real position.
       Gems use sprites 1..64 and never touch slot 0. */
    x16_mouse_offset();
    /* Hide the menu pointer while gameplay owns the sprite layer. */
    at(0x1FC00u + MENU_CURSOR_SLOT * 8u);
    VERA.data0 = 0;
    return 1;
}

void mouse_poll(void) {
    poll_raw();
}

void menu_mouse_init(void) {
    mouse_init();
    /* Palette offset 15 remaps hand indices 11/12 to 251/252.  Give the
       menu hand its own white/black pair so the title palette's index 15
       (dark red) cannot tint the glove. */
    at(0x1FA00u + 251u * 2u);
    VERA.data0 = 0xFF; VERA.data0 = 0x0F; /* white */
    at(0x1FA00u + 252u * 2u);
    VERA.data0 = 0x00; VERA.data0 = 0x00; /* black */
    upload_menu_cursor();
    draw_menu_cursor();
}

uint8_t menu_mouse_update(void) {
    static uint16_t last_x;
    static uint8_t last_y;
    uint8_t result = 0;
    uint8_t down;

    poll_raw();
    if (mouse_x != last_x || mouse_y != last_y) result |= 2u;
    draw_menu_cursor();
    last_x = mouse_x;
    last_y = mouse_y;
    down = (uint8_t)(mouse_buttons != 0);
    if (down && !prev_button) result |= 1u;
    prev_button = down;
    return result;
}
