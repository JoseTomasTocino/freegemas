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
    #ifdef __vita__
        mMenuOptions = {"setMusic", "setSound", "setFiltering", "back"};
    #else
        mMenuOptions = {"setMusic", "setSound", "setFullscreen", "setFiltering", "back"};
    #endif

    updateButtonTexts();

    mMenuSelectedOption = 0;
    mMenuYStart = 150;
    mMenuYGap = 42;
    mMenuYEnd = mMenuYStart + (int) mMenuOptions.size() * mMenuYGap;

    mGame->getGameSounds()->loadResources();
}

void StateOptions::update(){

    if (mGame->isCursorVisible()) {
        // Update menu highlighting according to mouse position
        int mY = (int) mGame -> getMouseY();

        if(mY >= mMenuYStart && mY < mMenuYEnd)
        {
            mMenuSelectedOption = (mY - mMenuYStart) / mMenuYGap;
        }
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
        case SDLK_SPACE:
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
    mGame->getGameSounds()->playSoundSelect();

    if (mMenuSelectedOption == 0) {
        mMenuSelectedOption = mMenuOptions.size() - 1;
    } else {
        mMenuSelectedOption -= 1;
    }
}

void StateOptions::moveDown() {
    mGame->getGameSounds()->playSoundSelect();

    if (mMenuSelectedOption == mMenuOptions.size() - 1) {
        mMenuSelectedOption = 0;
    } else {
        mMenuSelectedOption += 1;
    }
}

void StateOptions::updateButtonTexts()
{
    vector<GoSDL::Image> renderedTexts;

    // Option strings
    std::string musicText = _("Music: ");
    std::string soundText = _("Sound: ");
    std::string fullscreenText = _("Fullscreen: ");
    std::string filteringText = _("Scale quality: ");

    musicText += std::string(mOptions.getMusicEnabled() ? _("On") : _("Off"));
    soundText += std::string(mOptions.getSoundEnabled() ? _("On") : _("Off"));
    fullscreenText += std::string(mOptions.getFullscreenEnabled() ? _("On") : _("Off"));
    filteringText += std::string(mOptions.getFilteringEnabled() ? _("Linear") : _("Nearest"));

    // Menu text items
    SDL_Color menuTextColor = {255, 255, 255, 255}, menuShadowColor = {0,0,0, 128};
    renderedTexts.push_back(mFont.renderTextWithShadow(musicText, menuTextColor, 0, 2, menuShadowColor));
    renderedTexts.push_back(mFont.renderTextWithShadow(soundText, menuTextColor, 0, 2, menuShadowColor));
    #ifndef __vita__
        renderedTexts.push_back(mFont.renderTextWithShadow(fullscreenText, menuTextColor, 0, 2, menuShadowColor));
    #endif
    renderedTexts.push_back(mFont.renderTextWithShadow(filteringText, menuTextColor, 0, 2, menuShadowColor));
    renderedTexts.push_back(mFont.renderTextWithShadow(_("Back"), menuTextColor, 0, 2, menuShadowColor));

    mMenuRenderedTexts.swap(renderedTexts);
}

void StateOptions::optionChosen()
{
    string option = mMenuOptions[mMenuSelectedOption];
    if (option == "back") {
        mGame -> changeState("stateMainMenu");
    } else {
        if (option == "setMusic") {
            mOptions.setMusicEnabled(!mOptions.getMusicEnabled());
        } else if (option == "setSound") {
            mOptions.setSoundEnabled(!mOptions.getSoundEnabled());
            mGame->getGameSounds()->loadResources();
        } else if (option == "setFullscreen") {
            mOptions.setFullscreenEnabled(!mOptions.getFullscreenEnabled());
            mGame->setFullscreen(mOptions.getFullscreenEnabled());
        } else if (option == "setFiltering") {
            mOptions.setFilteringEnabled(!mOptions.getFilteringEnabled());
            mGame->setFiltering(mOptions.getFilteringEnabled());
        }
        updateButtonTexts();
    }
}

StateOptions::~StateOptions()
{
    lDEBUG << Log::DES("StateOptions");
}
