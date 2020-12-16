#include "StateGameEndless.h"

StateGameEndless::StateGameEndless(Game * game) : StateGame(game) {
}

void StateGameEndless::update()
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

        mGameIndicators.disableTime();

        // Reset the scoreboard
        mGameIndicators.setScore(0);
    }

    // Compute remaining time
    //double remainingTime = 10;

    mGameIndicators.updateTime(-1);

    // if (remainingTime <= 0)
    // {
    //     // Tell the board that the game ended with the given score
    //     mGameBoard.endGame(mGameIndicators.getScore());
    // }

    mGameBoard.update();
}
