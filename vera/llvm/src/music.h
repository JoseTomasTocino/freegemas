#ifndef FREEGEMAS_MUSIC_H
#define FREEGEMAS_MUSIC_H
#include <stdint.h>
/* Streamed signed 8-bit PCM music (MUSIC.PCM), mixed with the PCM effects. */
void music_init(void);
void music_tick(void);
void music_stop(void);
void music_restart(void);
/* VSYNC ticks elapsed, from the PCM samples the FIFO accepted (real time). */
uint8_t music_frames_elapsed(void);
#endif
