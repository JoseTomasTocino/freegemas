#include "StateGame.h"

#include "Game.h"

#include <map>
#include <string>

StateGame::StateGame(Game * p) : State(p)
{
    lDEBUG << Log::CON("StateGame");

    setState(eInitial);

    // Initialise game indicator
    mGameIndicators.setGame(p, this);

    // Initialise game board
    mGameBoard.setGame(p, this);

    // Load the loading screen
    mImgLoadingBanner.setWindowAndPath(p, "media/loadingBanner.png");
}

StateGame::~StateGame ()
{
    lDEBUG << Log::DES("StateGame");
}

void StateGame::update()
{
    // On the eInitial state, don't do anything about logic
    if (mState == eInitial)
    {
        return;
    }

    // On this state, start loading the resources
    else if (mState == eStartLoading)
    {
        loadResources();
        setState(eSteady);

        // Start the clock
        resetTime();

        // Reset the scoreboard
        mGameIndicators.setScore(0);
    }

    // Compute remaining time
    double remainingTime = (mTimeStart - SDL_GetTicks()) / 1000;

    mGameIndicators.updateTime(remainingTime);

    if (remainingTime <= 0)
    {
        // Tell the board that the game ended with the given score
        mGameBoard.endGame(mGameIndicators.getScore());
    }

    mGameBoard.update();
}

void StateGame::draw()
{
    // On this state, show the loading screen and switch the state
    if (mState == eInitial)
    {
        mImgLoadingBanner.draw(156, 200, 2);
        setState(eStartLoading);

        return;
    }

    // In all the other states, the full window is drawn
    mImgBoard.draw(0,0,0);

    // Draw the indicators (buttons and labels)
    mGameIndicators.draw();

    // Draw the main game board
    mGameBoard.draw();
}

void StateGame::buttonDown(SDL_Keycode button)
{
    if (button == SDLK_ESCAPE)
    {
        mGame -> changeState("stateMainMenu");
    }

    else if (button == SDLK_h)
    {
        showHint();
    }
}

void StateGame::mouseButtonDown(Uint8 button)
{
    // Left mouse button was pressed
    if (button == SDL_BUTTON_LEFT)
    {
        mMousePressed = true;

        // Get click location
        int mouseX = mGame->getMouseX();
        int mouseY = mGame->getMouseY();

        // Inform the UI
        mGameIndicators.click(mouseX, mouseY);

        // Inform the board
        mGameBoard.mouseButtonDown(mouseX, mouseY);
    }
}

void StateGame::mouseButtonUp(Uint8 button)
{
    // Left mouse button was released
    if (button == SDL_BUTTON_LEFT)
    {
        mMousePressed = false;

        // Get click location
        int mouseX = mGame->getMouseX();
        int mouseY = mGame->getMouseY();

        // Inform the board
        mGameBoard.mouseButtonUp(mouseX, mouseY);
    }
}

void StateGame::setState (tState state)
{
    // static std::map<tState, std::string> stateToString = {
    //     { eInitial, "eInitial"},
    //     { eStartLoading, "eStartLoading"},
    //     { eLoading, "eLoading"},
    //     { eLaunched, "eLaunched"},
    //     { eNewGemsFalling, "eNewGemsFalling"},
    //     { eOldGemsFalling, "eOldGemsFalling"},
    //     { eWaiting, "eWaiting"},
    //     { eGemSelected, "eGemSelected"},
    //     { eGemsSwitching, "eGemsSwitching"},
    //     { eGemsDisappearing, "eGemsDisappearing"},
    //     { eFirstFlip, "eFirstFlip"},
    //     { eInicialGemas, "eInicialGemas"},
    //     { eEspera, "eEspera"},
    //     { eGemaMarcada, "eGemaMarcada"},
    //     { eGemasCambiando, "eGemasCambiando"},
    //     { eGemasDesapareciendo, "eGemasDesapareciendo"},
    //     { eGemasNuevasCayendo, "eGemasNuevasCayendo"},
    //     { eDesapareceBoard, "eDesapareceBoard"},
    //     { eTimeFinished, "eTimeFinished"},
    //     { eShowingScoreTable, "eShowingScoreTable"}
    // };

    // lDEBUG << "New state: " << stateToString[state];
    mState = state;
}

// ----------------------------------------------------------------------------

void StateGame::loadResources()
{
    // Load the background image
    mImgBoard.setWindowAndPath(mGame, "media/board.png");

    mGameIndicators.loadResources();
    mGameBoard.loadResources();
}

void StateGame::resetGame()
{
    resetTime();
    mGameBoard.resetGame();
}

void StateGame::resetTime()
{
    // Default time is 2 minutes
    mTimeStart = SDL_GetTicks() + 2 * 60 * 1000;
}

void StateGame::showHint()
{
    mGameBoard.showHint();
}

void StateGame::increaseScore (int amount)
{
    mGameIndicators.increaseScore(amount);
}

