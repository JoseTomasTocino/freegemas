#ifndef FREEGEMAS_BOARD_H
#define FREEGEMAS_BOARD_H

#include <stdint.h>

enum { BOARD_W = 8, BOARD_H = 8, GEM_TYPES = 7, GEM_EMPTY = 0 };

typedef struct {
    uint8_t cells[BOARD_H][BOARD_W];
    uint16_t rng;
} Board;

void board_seed(Board *b, uint16_t seed);
void board_generate(Board *b);
uint8_t board_has_match(const Board *b);
uint8_t board_has_solution(Board *b);
uint8_t board_find_solution(Board *b, uint8_t *x, uint8_t *y, uint8_t *dx, uint8_t *dy);
uint8_t board_swap_creates_match(Board *b, uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2);
uint8_t board_mark_matches(const Board *b, uint8_t marked[BOARD_H][BOARD_W]);
uint8_t board_score_matches(const Board *b);
void board_clear_and_refill(Board *b, const uint8_t marked[BOARD_H][BOARD_W]);

#endif
