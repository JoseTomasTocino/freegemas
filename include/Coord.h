#ifndef COORD_H
#define COORD_H

#include <iostream>

/**
 * Represents a 2D coordinate.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 */
struct Coord
{
    /// Horizontal position
    int x;

    /// Vertical position
    int y;

    /// Default constructor
    Coord(int x = -1, int y = -1)
        : x(x), y(y)
    { }

    bool equals (int lx, int ly) const
    {
        return (x == lx && y == ly);
    }

    bool operator ==(const Coord & c) const
    {
        return (c.x == x && c.y == y);
    }

    bool operator !=(const Coord & c) const
    {
        return !(c.x == x && c.y == y);
    }

    friend std::ostream& operator << (std::ostream& out, Coord & C)
    {
        out << "(" << C.x << "," << C.y << ")";

        return out;
    }
};

#endif
