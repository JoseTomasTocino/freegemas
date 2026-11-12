#ifndef HISCORE_H
#define HISCORE_H
#include <stdint.h>
#define HIGH_SCORES ((volatile uint32_t *)0x03E0)
#define HISCORE_DIRTY (*(volatile uint8_t *)0x03E8)
#define HISCORE_INIT (*(volatile uint8_t *)0x03E9)
#endif
