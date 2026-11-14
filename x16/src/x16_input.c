#include <stdint.h>
#include "apple2e.h"

/* A tiny input queue.  Cursor keys are delivered by the X16 "keyboard
 * joystick" (JOY(0)); letters and Space/Enter/Esc come from the R49
 * kbdbuf_get extapi.  A direction is queued only on its rising edge so holding
 * it does not race the cursor. */
static uint8_t queue[8];
static uint8_t q_head, q_tail;
static uint8_t prev_joy;
static uint8_t prev_buttons;

static void push(uint8_t key) {
    uint8_t next = (uint8_t)((q_head + 1u) & 7u);
    if (next == q_tail) return;
    queue[q_head] = key;
    q_head = next;
}

static void poll_input(void) {
    uint8_t buttons, dirs, pressed0, pressed1, newd;
    x16_kgetin();
    if (x16_key) {
        uint8_t k = x16_key;
        if (k == 0x1B || k == 0x0D || k == 0x20) push(k);
        else if (k == 'H' || k == 'h') push('H');
        else if (k == 'R' || k == 'r') push('R');
    }
    x16_kjoystick();
    if (x16_joy2 == 0xFFu) return;
    /* joystick_get uses active-low bits.  Byte 0: bit0 right, bit1 left,
     * bit2 down, bit3 up, bit4 START, bit5 SELECT, bit6 Y, bit7 B.
     * Byte 1: bit7 A, bit6 X, bit5 L, bit4 R.  Only A/B mean "select";
     * treating START (Enter) as select would inject a second Space when
     * Enter is used to open a menu. */
    pressed0 = (uint8_t)~x16_joy0;
    pressed1 = (uint8_t)~x16_joy1;
    buttons = (uint8_t)(((pressed0 & 0x80u) | (pressed1 & 0x80u)) ? 1u : 0u);
    if (buttons && !prev_buttons) push(0x20);
    prev_buttons = buttons;
    dirs = (uint8_t)(pressed0 & 0x0Fu);
    newd = (uint8_t)(dirs & (uint8_t)~prev_joy);
    prev_joy = dirs;
    if (!newd) return;
    if (newd & 0x02u) push(0x08);       /* left  */
    else if (newd & 0x01u) push(0x15);  /* right */
    else if (newd & 0x08u) push(0x0B);  /* up    */
    else if (newd & 0x04u) push(0x0Au); /* down  */
}

uint8_t kbd_pressed(void) {
    poll_input();
    return q_head != q_tail;
}

uint8_t kbd_read(void) {
    uint8_t k;
    if (q_head == q_tail) return 0;
    k = queue[q_tail];
    q_tail = (uint8_t)((q_tail + 1u) & 7u);
    return k;
}

void kbd_clear(void) {
    q_head = q_tail = 0;
}
