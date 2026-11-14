#ifndef FREEGEMAS_MUSIC_H
#define FREEGEMAS_MUSIC_H
#include <stdint.h>
/* ZCM (16-bit PCM) music streamed from HostFS, plus PCM sound effects. */
void music_init(void);
void music_tick(void);
void music_stop(void);
void music_restart(void);
void music_clock_reset(void);
/* VSYNC ticks elapsed since the previous call, clamped to at least one. */
uint8_t music_frames_elapsed(void);
#endif
