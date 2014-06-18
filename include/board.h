#ifndef _BOARD_H_
#define _BOARD_H_

#include <boost/foreach.hpp>

#include <algorithm>
#include <vector>
using namespace std;

#include <boost/array.hpp>

#include "log.h"
#include "coord.h"

/// Different kinds of gems in a square.
enum tSquare { sqEmpty, sqWhite, sqRed, sqPurple, sqOrange, sqGreen, sqYellow, sqBlue };

/**
 * @class Square
 *
 * @brief Represents a square in the board.
 *
 * It holds the kind of gem it holds, as well as some animation-related
 * attributes
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 *
 */


struct Square{
    /// Kind of gem this square is holding
    tSquare tipo;

    /// Constructs a new square.
    Square(const tSquare & t = sqEmpty) : origY(0), destY(0), mustFall(false){
        tipo = t;
    }

    bool operator==(const Square & C){
        return C.tipo == tipo;
    }

    bool operator==(const tSquare & t){
        return tipo == t;
    }

    operator tSquare(){ return tipo; }

    /// Initial position of the square
    int origY;

    /** Vertical offset.
     *
     * This counts the number of positions this square has to fall
     */

    int destY;

    /// Indicates whether the square has to fall or not
    bool mustFall;
};

/**
 * Standard class for a 2D coordinate.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 *
 */




/**
 * A group of matched squares.
 *
 */


class Match : public vector<coord>{
public:
    coord midSquare() const{
        return at(size() / 2);
    }

    /**
     * Checks if the given coordinate is matched within the group
     *
     * @param c The coordinates to look for.
     *
     * @return true if c was found among the coords in the group.
     */
    bool matched(coord c) {
        return (std::find(begin(), end(), c) != end());
    }

    friend ostream& operator << (ostream& out, Match & M){
        out << "Match (" << M.size() << "): ";
        for (size_t i = 0; i < M.size(); ++i)
        {
            out << M[i] << ", ";
        }

        return out;
    }
};

/**
 * Group of multiple matches.
 *
 */

class MultipleMatch : public vector<Match>{
public:

    /**
     * Checks if the given coordinate is matched in any of the matched groups.
     *
     * @param C The coordinates to look for
     *
     * @return true if C was found in any of the matches
     */
    bool matched(coord C){
        vector<Match>::iterator it;
        for(it = begin(); it != end(); ++it){
            if(it -> matched(C))
                return true;
        }
        return false;
    }

};

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

    ~Board();

    /// Swaps squares x1,y1 and x2,y2
    void swap(int x1, int y1, int x2, int y2);

    /// Empties square (x,y)
    void del(int x, int y);

    /// Generates a random board.
    void generate();

    /// Calculates squares' positions after deleting the matching gems.
    void calcFallMovements();

    /// Applies calculated positions on previous method
    void applyFall();

    /// Fills board's gaps with newly generated gems
    void fillSpaces();

    /// Checks if there are matching horizontal and/or vertical groups
    MultipleMatch check();

    /// Checks if current board has any possible valid movement
    vector<coord> solutions();

    /// Resets squares' animations
    void endAnimations();

    /// Matrix of squares
    boost::array< boost::array<Square, 8>, 8> squares;

    friend ostream& operator <<(ostream& out, Board & B);
};
#endif /* _BOARD_H_ */
