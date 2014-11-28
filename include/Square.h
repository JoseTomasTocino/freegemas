#ifndef SQUARE_H
#define SQUARE_H

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


struct Square
{
    /// Kind of gem this square is holding
    tSquare tipo;

    /// Constructs a new square.
    Square(const tSquare & t = sqEmpty)
        : origY(0), destY(0), mustFall(false)
    {
        tipo = t;
    }

    bool operator==(const Square & C)
    {
        return C.tipo == tipo;
    }

    bool operator==(const tSquare & t)
    {
        return tipo == t;
    }

    operator tSquare()
    {
        return tipo;
    }

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

#endif