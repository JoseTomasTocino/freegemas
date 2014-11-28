#ifndef MULTIPLE_MATCH_H
#define MULTIPLE_MATCH_H

#include <vector>

#include "Match.h"

/**
 * Group of multiple matches.
 *
 */

class MultipleMatch : public std::vector<Match>
{
public:

    /**
     * Checks if the given coordinate is matched in any of the matched groups.
     *
     * @param C The coordinates to look for
     *
     * @return true if C was found in any of the matches
     */
    bool matched(Coord C)
    {
        vector<Match>::iterator it;
        for(it = begin(); it != end(); ++it)
        {
            if(it -> matched(C))
                return true;
        }
        return false;
    }

};

#endif