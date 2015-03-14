/**
 * @file ScoreTable.h
 *
 * @author José Tomás Tocino García
 * @date 2010
 *
 * Copyright (C) 2010 José Tomás Tocino García <theom3ga@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301, USA.
 */


#ifndef _SCORETABLE_
#define _SCORETABLE_


#include "go_image.h"


class Game;

/**
 * @class ScoreTable
 *
 * @brief Represents a table of scores that appears at the end of the game.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 *
 */

class ScoreTable{

public:

    /// Creates a new score table for the given amount of points
    ScoreTable(Game * p, int);

    /// Draws the score table at the given position
    void draw(int x, int y, int z);

private:

    /// Image for the rendered header
    GoSDL::Image mRenderedHeader;

    /// Image for the rendered score
    GoSDL::Image mRenderedScore;

    /// Image for the last high score
    GoSDL::Image mRenderedLastScore;

    /// Width of the score board
    int scoreBoardWidth;

    /// Reference to the main game
    Game * mGame;
};

#endif
