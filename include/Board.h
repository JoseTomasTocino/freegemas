#ifndef _BOARD_H_
#define _BOARD_H_

#include <array>
using namespace std;

#include "log.h"
#include "Square.h"
#include "MultipleMatch.h"


/**
 * @class Board
 *
 * @brief A game board.
 *
 * It's got a 8x8 matrix with the contents of the board, as well as some
 * algorithms to work with the board.
 *
 */

class Board{
public:
    Board();

    /// Swaps squares x1,y1 and x2,y2
    void swap(int x1, int y1, int x2, int y2);

    /// Empties square (x,y)
    void del(int x, int y);

    /// Generates a random board.
    void generate();

    /// Calculates squares' positions after deleting the matching gems, also filling the new spaces
    void calcFallMovements();

    /// Places all the gems out of the screen
    void dropAllGems();

    /// Checks if there are matching horizontal and/or vertical groups
    MultipleMatch check();

    /// Checks if current Board.has any possible valid movement
    vector<Coord> solutions();

    /// Resets squares' animations
    void endAnimations();

    /// Matrix of squares
    std::array< std::array<Square, 8>, 8> squares;

    friend ostream& operator <<(ostream& out, Board & B);
};

#endif
