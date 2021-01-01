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

    if (!mGameBoard.hasSolution()) {
        mGameBoard.endGame(mGameIndicators.getScore());
    }
    mGameBoard.update();
}
