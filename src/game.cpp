#include "game.h"
#include "state.h"

#include "stateMainMenu.h"
#include "stateHowtoplay.h"
#include "stateGame.h"


Game::Game ()
    : GoSDL::Window(800, 600, "FreeGemas")
{

    mMouseCursor.setWindow(this);
    mMouseCursor.setPath("media/handCursor.png");

    SDL_ShowCursor(0);

    changeState("stateMainMenu");
}

Game::~Game() {

}

void Game::update () {
    if (mCurrentState)
        mCurrentState -> update();
}

void Game::draw () {
    mMouseCursor.draw(getMouseX(), getMouseY(), 999);

    if (mCurrentState)
        mCurrentState -> draw();
}

void Game::buttonDown (SDL_Keycode button) {
    if (mCurrentState)
        mCurrentState -> buttonDown(button);
}

void Game::buttonUp (SDL_Keycode button) {
    if (mCurrentState)
        mCurrentState -> buttonUp(button);
}

void Game::mouseButtonDown (Uint8 button) {
    if (mCurrentState)
        mCurrentState -> mouseButtonDown(button);
}

void Game::mouseButtonUp (Uint8 button) {
    if (mCurrentState)
        mCurrentState -> mouseButtonUp(button);
}

void Game::changeState(string S){
    if(S == mCurrentStateString)
        return;

    if(S == "stateMainMenu"){
        mCurrentState . reset(new StateMainMenu(this));
        mCurrentStateString = "stateMainMenu";
    }
    else if(S == "stateGame"){
        mCurrentState . reset(new StateGame(this));
        mCurrentStateString = "estadoGame";
    }
    else if(S == "stateHowtoplay"){
        mCurrentState . reset(new StateHowtoplay(this));
        mCurrentStateString = "stateHowtoplay";
    }
    else if(S == "stateQuit"){
        close();
    }
}
