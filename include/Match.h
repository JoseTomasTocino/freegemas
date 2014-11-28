#ifndef MATCH_H
#define MATCH_H

#include <vector>
#include <algorithm>
#include <iostream>

#include "Coord.h"

/**
 * A group of matched squares.
 *
 */


class Match : public std::vector<Coord>
{
public:
    Coord midSquare() const
    {
        return at(size() / 2);
    }

    /**
     * Checks if the given coordinate is matched within the group
     *
     * @param c The coordinates to look for.
     *
     * @return true if c was found among the coords in the group.
     */
    bool matched (Coord c)
    {
        return (std::find(begin(), end(), c) != end());
    }

    friend std::ostream& operator << (std::ostream& out, Match & M)
    {
        out << "Match (" << M.size() << "): ";
        for (size_t i = 0; i < M.size(); ++i)
        {
            out << M[i] << ", ";
        }

        return out;
    }
};

#endif