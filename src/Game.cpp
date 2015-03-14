#include "Game.h"
#include "State.h"

#include "StateMainMenu.h"
#include "StateHowToPlay.h"
#include "StateGame.h"


Game::Game ()
    : GoSDL::Window(800, 600, "FreeGemas")
{
    lDEBUG << Log::CON("Game");

    mMouseCursor.setWindow(this);
    mMouseCursor.setPath("media/handCursor.png");

    hideCursor();

    changeState("stateMainMenu");
}

Game::~Game()
{
    lDEBUG << Log::DES("Game");
}

void Game::update ()
{
    if (mCurrentState)
        mCurrentState -> update();
}

void Game::draw ()
{
    mMouseCursor.draw(getMouseX(), getMouseY(), 999);

    if (mCurrentState)
        mCurrentState -> draw();
}

void Game::buttonDown (SDL_Keycode button)
{
    if (mCurrentState)
        mCurrentState -> buttonDown(button);
}

void Game::buttonUp (SDL_Keycode button)
{
    if (mCurrentState)
        mCurrentState -> buttonUp(button);
}

void Game::mouseButtonDown (Uint8 button)
{
    if (mCurrentState)
        mCurrentState -> mouseButtonDown(button);
}

void Game::mouseButtonUp (Uint8 button)
{
    if (mCurrentState)
        mCurrentState -> mouseButtonUp(button);
}

void Game::changeState(string S)
{
    if(S == mCurrentStateString)
    {
        return;
    }
    else if(S == "stateMainMenu")
    {
        mCurrentState = std::make_shared<StateMainMenu>(this);
        mCurrentStateString = "stateMainMenu";
    }
    else if(S == "stateGame")
    {
        mCurrentState = std::make_shared<StateGame>(this);
        mCurrentStateString = "estadoGame";
    }
    else if(S == "stateHowtoplay")
    {
        mCurrentState = std::make_shared<StateHowtoplay>(this);
        mCurrentStateString = "stateHowtoplay";
    }
    else if(S == "stateQuit")
    {
        close();
    }
}
