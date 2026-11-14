#include "board.h"
#include "frame_pump.h"

static uint8_t random_gem(Board *b) {
    b->rng ^= (uint16_t)(b->rng << 7);
    b->rng ^= b->rng >> 9;
    b->rng ^= (uint16_t)(b->rng << 8);
    return (uint8_t)(b->rng % GEM_TYPES) + 1;
}

void board_seed(Board *b, uint16_t seed) { b->rng = seed ? seed : 0xACE1; }

uint8_t board_mark_matches(const Board *b, uint8_t m[BOARD_H][BOARD_W]) {
    uint8_t x, y, n = 0;
    for (y = 0; y < BOARD_H; ++y) for (x = 0; x < BOARD_W; ++x) m[y][x] = 0;
    for (y = 0; y < BOARD_H; ++y) {
        x = 0;
        while (x < BOARD_W) {
            uint8_t start = x, gem = b->cells[y][x];
            while (x < BOARD_W && gem && b->cells[y][x] == gem) ++x;
            if ((uint8_t)(x - start) >= 3) while (start < x) { m[y][start++] = 1; n = 1; }
            if (!gem) ++x;
        }
    }
    for (x = 0; x < BOARD_W; ++x) {
        y = 0;
        while (y < BOARD_H) {
            uint8_t start = y, gem = b->cells[y][x];
            while (y < BOARD_H && gem && b->cells[y][x] == gem) ++y;
            if ((uint8_t)(y - start) >= 3) while (start < y) { m[start++][x] = 1; n = 1; }
            if (!gem) ++y;
        }
    }
    return n;
}

uint8_t board_has_match(const Board *b) { uint8_t m[8][8]; return board_mark_matches(b, m); }

/* Return the sum of all maximal horizontal and vertical match lengths.
 * The original game scores Match objects separately, so the crossing gem in
 * a T/L/cross belongs to (and scores in) both groups. */
uint8_t board_score_matches(const Board *b) {
    uint8_t x, y, total = 0;
    for (y = 0; y < BOARD_H; ++y) {
        x = 0;
        while (x < BOARD_W) {
            uint8_t start = x, gem = b->cells[y][x];
            while (x < BOARD_W && gem && b->cells[y][x] == gem) ++x;
            if ((uint8_t)(x - start) >= 3) total += (uint8_t)(x - start);
            if (!gem) ++x;
        }
    }
    for (x = 0; x < BOARD_W; ++x) {
        y = 0;
        while (y < BOARD_H) {
            uint8_t start = y, gem = b->cells[y][x];
            while (y < BOARD_H && gem && b->cells[y][x] == gem) ++y;
            if ((uint8_t)(y - start) >= 3) total += (uint8_t)(y - start);
            if (!gem) ++y;
        }
    }
    return total;
}

/* Inspect a virtual exchange. Move searches must never change the live board
 * or accept a match elsewhere as evidence that this exchange is legal. */
static uint8_t swapped_gem(const Board *b, uint8_t x, uint8_t y,
                           uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2) {
    if (x == x1 && y == y1) return b->cells[y2][x2];
    if (x == x2 && y == y2) return b->cells[y1][x1];
    return b->cells[y][x];
}

static uint8_t swap_matches_at(const Board *b, uint8_t x, uint8_t y,
                              uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2) {
    uint8_t axis, count, gem = swapped_gem(b,x,y,x1,y1,x2,y2);
    int8_t direction, px, py;
    if (!gem) return 0;
    for (axis = 0; axis < 2; ++axis) {
        count = 1;
        for (direction = -1; direction <= 1; direction += 2) {
            px = (int8_t)x; py = (int8_t)y;
            for (;;) {
                if (axis) py += direction; else px += direction;
                if (px < 0 || px >= 8 || py < 0 || py >= 8 ||
                    swapped_gem(b,(uint8_t)px,(uint8_t)py,x1,y1,x2,y2) != gem) break;
                if (++count >= 3) return 1;
            }
        }
    }
    return 0;
}

uint8_t board_swap_creates_match(Board *b, uint8_t x1, uint8_t y1, uint8_t x2, uint8_t y2) {
    if (x1 > 7 || y1 > 7 || x2 > 7 || y2 > 7 || (uint8_t)((x1 > x2 ? x1-x2 : x2-x1) + (y1 > y2 ? y1-y2 : y2-y1)) != 1) return 0;
    if (!b->cells[y1][x1] || !b->cells[y2][x2] || b->cells[y1][x1] == b->cells[y2][x2]) return 0;
    return swap_matches_at(b,x1,y1,x1,y1,x2,y2) || swap_matches_at(b,x2,y2,x1,y1,x2,y2);
}

uint8_t board_has_solution(Board *b) {
    uint8_t x, y, dx, dy;
    return board_find_solution(b, &x, &y, &dx, &dy);
}

uint8_t board_find_solution(Board *b, uint8_t *rx, uint8_t *ry, uint8_t *rdx, uint8_t *rdy) {
    uint8_t x, y;
    /* A dead board scans all 128 swaps, several VSYNCs of CPU work; feed the
     * PCM queue from inside the scan or the audio drains while the player
     * waits for the reshuffle. */
    for (y = 0; y < 8; ++y) {
        frame_pump();
        for (x = 0; x < 8; ++x)
            if (x < 7 && board_swap_creates_match(b,x,y,x+1,y)) { *rx=x; *ry=y; *rdx=1; *rdy=0; return 1; }
            else if (y < 7 && board_swap_creates_match(b,x,y,x,y+1)) { *rx=x; *ry=y; *rdx=0; *rdy=1; return 1; }
    }
    return 0;
}

void board_generate(Board *b) {
    uint8_t x, y;
    do {
        frame_pump();
        for (y=0;y<8;++y) for (x=0;x<8;++x) b->cells[y][x] = random_gem(b);
    } while (board_has_match(b) || !board_has_solution(b));
}

void board_clear_and_refill(Board *b, const uint8_t m[8][8]) {
    uint8_t x, y, out;
    for (x=0;x<8;++x) { out=7; for (y=8;y--;) if (!m[y][x]) b->cells[out--][x]=b->cells[y][x]; while ((int8_t)out>=0) b->cells[out--][x]=random_gem(b); }
}
