#ifndef GAME_HINT_H
#define GAME_HINT_H

#include "Coord.h"

#include "go_window.h"
#include "go_image.h"

class GameHint
{
public:
    /// Sets the parent window and loads the resources
    void setWindow (GoSDL::Window * w);

    /// Places the hint at the specified position and shows it
    void showHint(Coord location);

    /// Draws the hint (if necessary)
    void draw();

private:

    /// Total initial animation steps
    int mAnimationCurrentStep = 0;

    /// Steps for the hint animation
    int mAnimationTotalSteps = 40;

    /// Hint flag
    int mShowingHint = false;

    /// Coordinates for the hint
    Coord mHintLocation;

    /// Image for the hint
    GoSDL::Image mImgSelector;
};

#endif