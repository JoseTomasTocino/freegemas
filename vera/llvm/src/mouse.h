#ifndef FREEGEMAS_MOUSE_H
#define FREEGEMAS_MOUSE_H

#include <stdint.h>

/* Apple Mouse Card firmware driver. Coordinates are clamped to the VERA
 * game's 320x240 screen; buttons bit 7 is set while the primary button is down. */
extern volatile uint16_t mouse_x;
extern volatile uint8_t mouse_y;
extern volatile uint8_t mouse_buttons;
extern volatile uint8_t mouse_slot;

uint8_t mouse_init(void);
void mouse_poll(void);

#endif
