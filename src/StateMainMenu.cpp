#include "StateMainMenu.h"

#include "Game.h"
#include "log.h"
#include "inter.h"

#include "go_font.h"

#include <cmath>
#include <tuple>


template <typename T, typename R>

T clamp(T v, R bottom, R top)
{
    if(v > top) return top;
    if(v < bottom) return bottom;
    return v;
}

StateMainMenu::StateMainMenu(Game * p) : State(p)
{
    lDEBUG << Log::CON("StateMainMenu");

    mCurrentTransitionState = TransitionIn;

    // Init background image
    mImgBackground.setWindow(p);
    mImgBackground.setPath("media/stateMainMenu/mainMenuBackground.png");

    // Init logo image
    mImgLogo.setWindow(p);
    mImgLogo.setPath("media/stateMainMenu/mainMenuLogo.png");

    // Init menu highlight image
    mImgHighl.setWindow(p);
    mImgHighl.setPath("media/stateMainMenu/menuHighlight.png");

    // Load the font
    mFont.setWindow(p);
    mFont.setPathAndSize("media/fuenteMenu.ttf", 30);

    // Menu target states
    mMenuTargets = {"stateGame", "stateHowtoplay", "stateQuit"};

    // Menu text items
    SDL_Color menuTextColor = {255, 255, 255, 255};
    mMenuRenderedTexts.push_back(mFont.renderText(_("Timetrial mode"), menuTextColor));
    mMenuRenderedTexts.push_back(mFont.renderText(_("How to play?"), menuTextColor));
    mMenuRenderedTexts.push_back(mFont.renderText(_("Exit"), menuTextColor));

    // Menu shadows
    menuTextColor = {0,0,0, 255};
    mMenuRenderedShadows.push_back(mFont.renderText(_("Timetrial mode"), menuTextColor));
    mMenuRenderedShadows.push_back(mFont.renderText(_("How to play?"), menuTextColor));
    mMenuRenderedShadows.push_back(mFont.renderText(_("Exit"), menuTextColor));

    // Jewel group animation
    mJewelAnimation.loadResources(p);

    mAnimationTotalSteps = 30;
    mAnimationLogoSteps = 30;
    mAnimationCurrentStep = 0;

    mMenuSelectedOption = 0;
    mMenuYStart = 350;
    mMenuYGap = 42;
    mMenuYEnd = 350 + (int) mMenuTargets.size() * mMenuYGap;
}

void StateMainMenu::update(){

    if(mCurrentTransitionState == TransitionIn)
    {
        mAnimationCurrentStep ++;

        if(mAnimationCurrentStep == mAnimationTotalSteps)
        {
            mCurrentTransitionState = Active;
        }

    } else if(mCurrentTransitionState == Active){

    } else if(mCurrentTransitionState == TransitionOut){

    }

    // Update menu highlighting according to mouse position
    int mY = (int) mGame -> getMouseY();

    if(mY >= mMenuYStart && mY < mMenuYEnd)
    {
        mMenuSelectedOption = (mY - mMenuYStart) / mMenuYGap;
    }
}

void StateMainMenu::draw(){

    // Draw the background
    mImgBackground.draw(0, 0, 1);

    // Calculate the alpha value for the logo
    int logoAlfa = clamp( (int)(255 * (float)mAnimationCurrentStep / mAnimationLogoSteps),
                          0, 255);

    // Draw the logo
    mImgLogo.draw(86, 0, 2, 1, 1, 0, logoAlfa);

    // Loop to draw the menu items
    for(size_t i = 0, s = (int) mMenuTargets.size(); i < s; ++i)
    {
        // Calculate the horizontal and vertical positions
		int posX = std::round(800 / 2 - mMenuRenderedTexts[i].getWidth() / 2),
            posY = mMenuYStart + i * mMenuYGap;

        // Draw the text and the shadow
        mMenuRenderedTexts[i].draw(posX, posY, 3);
        mMenuRenderedShadows[i].draw(posX, posY + 2, 2.9, 1, 1, 0, 128);

    }

    // Draw the menu highlighting
    mImgHighl.draw(266, mMenuYStart + 5 + mMenuSelectedOption * mMenuYGap, 2);

    // Draw the jewel animation
    mJewelAnimation.draw();
    //*/
}

void StateMainMenu::buttonDown(SDL_Keycode button)
{
    switch (button)
    {
        case SDLK_ESCAPE:
            mGame->close();
            break;

        case SDLK_DOWN:
            mMenuSelectedOption = (mMenuSelectedOption + 1) % mMenuTargets.size();
            break;

        case SDLK_UP:
            mMenuSelectedOption = (mMenuSelectedOption - 1) % mMenuTargets.size();
            break;

        case SDLK_RETURN:
        case SDLK_KP_ENTER:
            optionChosen();
            break;
    }
}

void StateMainMenu::mouseButtonDown(Uint8 button)
{
    if (button == SDL_BUTTON_LEFT)
    {

        // Get mouse vertical position
        int mY = mGame->getMouseY();

        if (mY >= mMenuYStart && mY <= mMenuYEnd)
        {
            optionChosen();
        }
    }
}

void StateMainMenu::optionChosen()
{
    mGame -> changeState(mMenuTargets[mMenuSelectedOption]);
}

StateMainMenu::~StateMainMenu()
{
    lDEBUG << Log::DES("StateMainMenu");
}
