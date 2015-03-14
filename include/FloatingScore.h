/**
 * @file FloatingScore.h
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


#ifndef _FLOATINGSCORE_H_
#define _FLOATINGSCORE_H_

#include <string>
using namespace std;

#include "log.h"
#include "go_image.h"
#include "go_font.h"

namespace GoSDL {
  class Window;
}

class FloatingScore{
public:
    FloatingScore(GoSDL::Window * parentWindow, int score, float x, float y, float z) :
        x_(x), y_(y), z_(z), mCurrentStep(0), mTotalSteps(50) {

        // Load the font
        GoSDL::Font tempFont;
        tempFont.setAll(parentWindow, "media/fuentelcd.ttf", 60);

        // Build the image
        mScoreImage = tempFont.renderText(std::to_string(score), {255, 255, 255, 255});
        mScoreImageShadow = tempFont.renderText(std::to_string(score), {0, 0, 0, 255});
    }

    bool ended(){
        return mCurrentStep == mTotalSteps;
    }

    void draw(){
        if(mCurrentStep >= mTotalSteps) return;

        mCurrentStep += 1;

        float p = 1.f - (float)mCurrentStep/mTotalSteps;

        float posX = 241 + x_ * 65;
        float posY = 41 + y_ * 65 - (1 - p) * 20;

        mScoreImage.draw(posX, posY, z_, 1, 1, 0, (int)(p * 255));

        mScoreImageShadow.draw(posX + 2, posY + 2, z_ - 0.1, 1, 1, 0, (int)(p * 255));

        mScoreImageShadow.draw(posX - 2, posY - 2, z_ - 0.1, 1, 1, 0, (int)(p * 255));

    }
private:
    GoSDL::Image mScoreImage;
    GoSDL::Image mScoreImageShadow;

    float x_;
    float y_;
    float z_;

    int mCurrentStep;
    int mTotalSteps;


};

#endif /* _FLOATINGSCORE_H_ */
