#ifndef EFFECTS_H
#define EFFECTS_H
#include "board.h"
/* Slot 0 belongs to the KERNAL mouse; gems use 1..64.  At equal z-depth the
 * lower slot wins, so the hand (65) is in front of the hint (66) and
 * cursor/selection (67/68), while the hint stays early enough to render
 * before VERA's sprite clock budget runs out. */
enum { EFFECT_MOUSE_SLOT = 65, EFFECT_HINT_SLOT = 66, EFFECT_CURSOR_SLOT = 67, EFFECT_SELECTION_SLOT = 68 };
void effects_init(void);
void effects_clear(void);
void effects_tick(void);
void effects_mouse(uint16_t x, uint8_t y);
void effects_cursor(uint8_t x, uint8_t y, uint8_t selected, uint8_t sx, uint8_t sy);
void effects_hint(uint8_t x, uint8_t y);
void effects_hide_hint(void);
void effects_matches(const Board *board, const uint8_t marks[8][8], uint8_t points, uint8_t multiplier);
#endif
