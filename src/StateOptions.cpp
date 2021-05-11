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

    mOptions.loadResources();

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
    mMenuOptions = {"setMusic", "setSound", "back"};

    updateButtonTexts();

    mMenuSelectedOption = 0;
    mMenuYStart = 150;
    mMenuYGap = 42;
    mMenuYEnd = mMenuYStart + (int) mMenuOptions.size() * mMenuYGap;

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
        mMenuSelectedOption = mMenuOptions.size() - 1;
    }
}

void StateOptions::moveDown() {
    mGameSounds.playSoundSelect();
    mMenuSelectedOption += 1;

   if (mMenuSelectedOption == mMenuOptions.size()) {
        mMenuSelectedOption = 0;
    }
}

void StateOptions::updateButtonTexts()
{
    vector<GoSDL::Image> renderedTexts;
    vector<GoSDL::Image> renderedShadows;

    // Option strings
    std::string musicText = _("Music: ");
    std::string soundText = _("Sound: ");

    musicText += std::string(mOptions.getMusicEnabled() ? _("On") : _("Off"));
    soundText += std::string(mOptions.getSoundEnabled() ? _("On") : _("Off"));

    // Menu text items
    SDL_Color menuTextColor = {255, 255, 255, 255};
    renderedTexts.push_back(mFont.renderText(musicText, menuTextColor));
    renderedTexts.push_back(mFont.renderText(soundText, menuTextColor));
    renderedTexts.push_back(mFont.renderText(_("Back"), menuTextColor));

    // Menu shadows
    menuTextColor = {0,0,0, 255};
    renderedShadows.push_back(mFont.renderText(_("Music"), menuTextColor));
    renderedShadows.push_back(mFont.renderText(_("Sound"), menuTextColor));
    renderedShadows.push_back(mFont.renderText(_("Back"), menuTextColor));

    mMenuRenderedTexts.swap(renderedTexts);
    mMenuRenderedShadows.swap(renderedShadows);
}

void StateOptions::optionChosen()
{
    string option = mMenuOptions[mMenuSelectedOption];
    if (option == "setMusic") {
        mOptions.setMusicEnabled(!mOptions.getMusicEnabled());
        updateButtonTexts();
    }
    if (option == "setSound") {
        mOptions.setSoundEnabled(!mOptions.getSoundEnabled());
        updateButtonTexts();
    }
    if (option == "back") {
        mGame -> changeState("stateMainMenu");
    }
}

StateOptions::~StateOptions()
{
    lDEBUG << Log::DES("StateOptions");
}
