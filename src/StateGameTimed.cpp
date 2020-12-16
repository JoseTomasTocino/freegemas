#include "StateGameTimed.h"

StateGameTimed::StateGameTimed(Game * p) : StateGame(p) {

}

void StateGameTimed::update()
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

        mGameIndicators.enableTime();

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