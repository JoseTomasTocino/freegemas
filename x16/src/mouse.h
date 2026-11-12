#ifndef FREEGEMAS_MOUSE_H
#define FREEGEMAS_MOUSE_H

#include <stdint.h>

/* Commander X16 KERNAL mouse state.  mouse_x/mouse_y are in the 320x240
 * game space; mouse_buttons uses bit 7 for the primary (left) button. */
extern volatile uint16_t mouse_x;
extern volatile uint8_t mouse_y;
extern volatile uint8_t mouse_buttons;
extern volatile uint8_t mouse_slot;

uint8_t mouse_init(void);
void mouse_poll(void);

#endif
