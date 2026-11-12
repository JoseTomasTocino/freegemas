#ifndef FREEGEMAS_FRAME_PUMP_H
#define FREEGEMAS_FRAME_PUMP_H
/* Pay one VSYNC worth of periodic work (music feed + effects) when the VSYNC
 * latch is already set.  The game loop in main.c provides it so that long
 * CPU-bound loops keep the music and the clock fed. */
void frame_pump(void);
#endif
