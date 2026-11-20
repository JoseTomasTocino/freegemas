#ifndef FREEGEMAS_MENU_MOUSE_H
#define FREEGEMAS_MENU_MOUSE_H
#include "mouse.h"
void menu_mouse_init(void);
/* Poll once per VSYNC; bit 0=primary press, bit 1=position changed. */
uint8_t menu_mouse_update(void);
#endif
