#include "StateOptions.h"

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

StateOptions::StateOptions(Game * p) : State(p)
{
    lDEBUG << Log::CON("StateOptions");

    // Init background image
    mImgBackground.setWindow(p);
    mImgBackground.setPath("media/stateMainMenu/mainMenuBackground.png");

    // Init menu highlight image
    mImgHighl.setWindow(p);
    mImgHighl.setPath("media/stateMainMenu/menuHighlight.png");

    // Load the font
    mFont.setWindow(p);
    mFont.setPathAndSize("media/fuenteMenu.ttf", 30);

    // Menu target states
    mMenuOptions = {"back"};

    // Menu text items
    SDL_Color menuTextColor = {255, 255, 255, 255};
    mMenuRenderedTexts.push_back(mFont.renderText(_("Back"), menuTextColor));

    // Menu shadows
    menuTextColor = {0,0,0, 255};
    mMenuRenderedShadows.push_back(mFont.renderText(_("Back"), menuTextColor));

    mMenuSelectedOption = 0;
    mMenuYStart = 150;
    mMenuYGap = 42;
    mMenuYEnd = 350 + (int) mMenuOptions.size() * mMenuYGap;

    mGameSounds.loadResources();
}

void StateOptions::update(){

    // Update menu highlighting according to mouse position
    int mY = (int) mGame -> getMouseY();

    if(mY >= mMenuYStart && mY < mMenuYEnd)
    {
        mMenuSelectedOption = (mY - mMenuYStart) / mMenuYGap;
    }
}

void StateOptions::draw(){

    // Draw the background
    mImgBackground.draw(0, 0, 1);

    // Loop to draw the menu items
    for(size_t i = 0, s = (int) mMenuOptions.size(); i < s; ++i)
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
}

void StateOptions::buttonDown(SDL_Keycode button)
{
    switch (button)
    {
        case SDLK_ESCAPE:
            mGame -> changeState("stateMainMenu");
            break;

        case SDLK_DOWN:
            moveDown();
            break;

        case SDLK_UP:
            moveUp();
            break;

        case SDLK_RETURN:
        case SDLK_KP_ENTER:
            optionChosen();
            break;
    }
}

void StateOptions::controllerButtonDown(Uint8 button)
{
    switch (button)
    {
        case SDL_CONTROLLER_BUTTON_A:
            optionChosen();
            break;

        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
            moveDown();
            break;

        case SDL_CONTROLLER_BUTTON_DPAD_UP:
            moveUp();
            break;
    }
}

void StateOptions::mouseButtonDown(Uint8 button)
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

void StateOptions::moveUp() {
    mGameSounds.playSoundSelect();
    mMenuSelectedOption -= 1;

   if (mMenuSelectedOption < 0) {
        mMenuSelectedOption = mMenuTargets.size() - 1;
    }
}

void StateOptions::moveDown() {
    mGameSounds.playSoundSelect();
    mMenuSelectedOption += 1;

   if (mMenuSelectedOption == mMenuTargets.size()) {
        mMenuSelectedOption = 0;
    }
}

void StateOptions::optionChosen()
{
    string option = mMenuOptions[mMenuSelectedOption];
    if (option == "back") {
        mGame -> changeState("stateMainMenu");
    }
}

StateOptions::~StateOptions()
{
    lDEBUG << Log::DES("StateOptions");
}
