/**
 * @file scoreTable.h
 * 
 * @author José Tomás Tocino García
 * @date 2010
 *
 * 
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

#include <Gosu/Gosu.hpp>

#include <boost/scoped_ptr.hpp>
#include <boost/bind.hpp>
#include <boost/lexical_cast.hpp>

#include <fstream>
#include <string>
#include <set>
#include <utility>
#include <algorithm>

using namespace std;

#include "log.h"
#include "game.h"
#include "resManager.h"


class Game;

/**
 * @class ScoreTable
 *
 * @brief Represents a table of scores that appears at the end of the game.
 *
 * 
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com> 
 *
 */


class ScoreTable{
public:

    /// Creates a new score table for the given amount of points
    ScoreTable(Game * p, int points);

    /// Draws the score table at the given position
    void draw(int x, int y, double z);

    /// Launches when a button is pressed
    void buttonDown(Gosu::Button B);

private:

    void fillEmptyScoreFile();

    /// Font for the first header
    boost::shared_ptr<CustomFont> fntH1;

    /// Font for the second header
    boost::shared_ptr<CustomFont> fntH2;

    /// LCD-style fonts for the content
    boost::shared_ptr<CustomFont> fntLcdBig, fntLcdSmall;

    /// Stream to access the file of scores
    fstream scoreFile;

    /// States of the score table
    enum tState{
        eRequestPlayerName,
        eShowScores
    };

    /// Current state of the table
    tState state;

    /// Functor to compare scores
    struct scoreComp{
        bool operator()(const pair<string,int> & A, const pair<string,int>& B){
            return A.second > B.second;
        }
    };

    /// Container of scores
    set<pair<string, int>, scoreComp > readScoreSet;

    /// Iterator for the score set
    typedef set<pair<string, int>, scoreComp >::iterator scoreSetIterator;

    /// Width of the score board
    int scoreBoardWidth;

    /// Reference to the main game
    Game * parent;

    /**
     * @class ScoreTableInput
     *
     * @brief Filter class for the input at the score table
     *
     * This class filters spaces from the user input
     *
     * @author José Tomás Tocino García <theom3ga@gmail.com> 
     *
     */
    

    class ScoreTableInput : public Gosu::TextInput{
    public:

        /** 
         * Filters spaces from the given string. Also checks whether the
         * complete text is no longer than 15 characters.
         * 
         * @param str_ the string to filter
         * 
         * @return the filtered string, without spaces
         */

        std::wstring filter(const std::wstring & str_) const{

            // If the length is higher than 15 characters, return the empty string
            if(text().length() == 15) 
                return L"";

            lDEBUG << "Filter: " << Gosu::narrow(str_);
            std::wstring returnString = str_.substr(0, 15);

            returnString.erase(
                std::remove_if(returnString.begin(), returnString.end(), 
                               boost::bind<bool>(std::equal_to<wchar_t>(), _1, L' ')), 
                returnString.end());
            
            return returnString;
        }

    };

    /// Instance of the input object that deals with the user input text
    ScoreTableInput nameInput;
    
    /// Points to show
    int points;
};

#endif
