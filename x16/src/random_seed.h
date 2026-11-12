#ifndef RANDOM_SEED_H
#define RANDOM_SEED_H
#include <stdint.h>
#include "apple2e.h"
/* The seed lives in the shared $9E00 page so it survives overlay reloads.
 * Menu timing is captured by mixing the running VSYNC counter, which keeps
 * advancing while the player sits on a title screen. */
static uint16_t random_ticks;
static void random_poll(void) {
    uint16_t seed = RANDOM_SEED;
    uint16_t t = (uint16_t)((uint8_t)(X16_FRAME + 1u) + ++random_ticks);
    RANDOM_SEED = (uint16_t)(((seed << 5) | (seed >> 11)) ^ t ^ (t << 7) ^ 0x9E37u);
}
#endif
