/**
 * @file BaseButton.h
 *
 * @author José Tomás Tocino García
 * @date 2011
 *
 * Copyright (C) 2011 José Tomás Tocino García <theom3ga@gmail.com>
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


#ifndef _BASEBUTTON_
#define _BASEBUTTON_

#include <string>
using namespace std;

// #include "resManager.h"
#include "log.h"
#include "go_image.h"

/**
 * @class BaseButton
 *
 * @brief Base for buttons on the interface.
 *
 * They have a caption and may also have an icon. The text is centered in the
 * button.
 *
 * @author José Tomás Tocino García <theom3ga@gmail.com>
 *
 */

class BaseButton{
public:

    BaseButton();

    void set (GoSDL::Window * parentWindow, std::string caption, std::string iconPath);
    void setText(std::string caption);

    void draw(int x, int y, double z);

    /**
     * Checks if the button was pressed. It uses the last drawing position to
     * check if the mouse was within boundaries.
     *
     * @param mX Horizontal mouse position
     * @param mY Vertical mouse position
     *
     * @return true if the button was pressed
     */
    bool clicked(unsigned int mX, unsigned int mY);

private:

    /// Parent window
    GoSDL::Window * mParentWindow;

    /// Image for the background of the button
    GoSDL::Image mImgBackground;

    /// Image for the icon of the button, may be null.
    GoSDL::Image mImgIcon;

    bool mHasIcon;

    /// Font used for the button's label
    GoSDL::Image mImgCaption, mImgCaptionShadow;

    /// Position of the label within the button
    int mTextHorizontalPosition;

    /// Last drawing position. It's used for the clicked method.
    unsigned int mLastX, mLastY;
};

#endif
