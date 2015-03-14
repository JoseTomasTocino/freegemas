#include "GameBoard.h"

#include "Game.h"
#include "StateGame.h"

using namespace std::placeholders;


void GameBoard::setGame(Game * game, StateGame * stateGame)
{
    mGame = game;
    mStateGame = stateGame;

    mBoard.generate();

    mState = eBoardAppearing;
    mAnimationCurrentStep = 0;
}

void GameBoard::resetGame()
{
    // Game can only be reset on the steady state, or when the Game.has ended
    if (mState != eSteady && mState != eShowingScoreTable)
        return;

    // Reset the variables
    mMultiplier = 0;
    mAnimationCurrentStep = 0;

    // If there's a board on screen, make it disappear first
    if (mState != eShowingScoreTable)
    {
        // Drop all gems
        mBoard.dropAllGems();

        // Switch state
        mState = eBoardDisappearing;
    }

    // Otherwise, directly generate and show the new board
    else {
        // Generate a brand new board
        mBoard.generate();

        // Switch state
        mState = eBoardAppearing;
    }

}

void GameBoard::endGame(int score)
{
    if (mState == eTimeFinished || mState == eShowingScoreTable)
        return;

    mBoard.dropAllGems();
    mState = eTimeFinished;

    // Generate the score table
    scoreTable = std::make_shared<ScoreTable>(mGame, score);
}

void GameBoard::loadResources()
{
    mImgBoard.setWindowAndPath(mGame, "media/gemBoard.png");
    mImgWhite.setWindowAndPath(mGame, "media/gemWhite.png");
    mImgRed.setWindowAndPath(mGame, "media/gemRed.png");
    mImgPurple.setWindowAndPath(mGame, "media/gemPurple.png");
    mImgOrange.setWindowAndPath(mGame, "media/gemOrange.png");
    mImgGreen.setWindowAndPath(mGame, "media/gemGreen.png");
    mImgYellow.setWindowAndPath(mGame, "media/gemYellow.png");
    mImgBlue.setWindowAndPath(mGame, "media/gemBlue.png");

    // Load the image for the square selector
    mImgSelector.setWindowAndPath(mGame, "media/selector.png");

    // Initialise the hint
    mHint.setWindow(mGame);

    // Initialise the sounds
    mGameBoardSounds.loadResources();
}

void GameBoard::update()
{
    // Default state, do nothing
    if (mState == eSteady)
    {
        mMultiplier = 0;
        mAnimationCurrentStep = 0;
    }

    // Board appearing, gems are falling
    else if (mState == eBoardAppearing)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished, switch to steady state
        if (mAnimationCurrentStep == mAnimationLongTotalSteps)
        {
            mState = eSteady;
        }
    }

    // Two winning gems are switching places
    else if (mState == eGemSwitching)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished, matching gems should disappear
        if (mAnimationCurrentStep == mAnimationShortTotalSteps)
        {
            // Winning games should disappear
            mState = eGemDisappearing;

            // Reset the animation
            mAnimationCurrentStep = 0;

            // Swap the gems in the board
            mBoard.swap(mSelectedSquareFirst.x, mSelectedSquareFirst.y,
                        mSelectedSquareSecond.x, mSelectedSquareSecond.y);

            // Increase the mMultiplier
            ++mMultiplier;

            // Play matching sound
            playMatchSound();

            // Create floating scores for the matching group
            createFloatingScores();
        }
    }

    // Matched gems are disappearing
    else if (mState == eGemDisappearing)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished
        if (mAnimationCurrentStep == mAnimationShortTotalSteps)
        {
            // Empty spaces should be filled with new gems
            mState = eBoardFilling;

            // Delete the squares that were matched in the board
            for(size_t i = 0; i < mGroupedSquares.size(); ++i)
            {
                for(size_t j = 0; j < mGroupedSquares[i].size(); ++j)
                {
                    mBoard.del(mGroupedSquares[i][j].x, mGroupedSquares[i][j].y);
                }
            }

            // Calculate fall movements
            mBoard.calcFallMovements();

            // Reset the animation
            mAnimationCurrentStep = 0;
        }
    }

    // New gems are falling to their proper places
    else if (mState == eBoardFilling)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished
        if (mAnimationCurrentStep == mAnimationShortTotalSteps)
        {
            // Play the fall sound
            mGameBoardSounds.playSoundFall();

            // Switch to the normal state
            mState = eSteady;

            // Reset the animation
            mAnimationCurrentStep = 0;

            // Reset animations in the board
            mBoard.endAnimations();

            // Check if there are matching groups
            mGroupedSquares = mBoard.check();

            // If there are...
            if (! mGroupedSquares.empty())
            {
                // Increase the score mMultiplier
                ++mMultiplier;

                // Create the floating scores
                createFloatingScores();

                // Play matching sound
                playMatchSound();

                // Go back to the gems-fading mState
                mState = eGemDisappearing;
            }

            // If there are neither current solutions nor possible future solutions
            else if (mBoard.solutions().empty())
            {
                // Make the board disappear
                mState = eBoardDisappearing;

                // Make all the gems want to go outside the board
                mBoard.dropAllGems();
            }
        }
    }

    // The entire board is disappearing to show a new one
    else if (mState == eBoardDisappearing)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished
        if (mAnimationCurrentStep == mAnimationLongTotalSteps)
        {
            // Reset animation counter
            mAnimationCurrentStep = 0;

            // Generate a brand new board
            mBoard.generate();

            // Switch state
            mState = eBoardAppearing;
        }
    }

    // The board is disappearing because the time has run out
    else if (mState == eTimeFinished)
    {
        // Update the animation frame
        mAnimationCurrentStep ++;

        // If the Animation.has finished
        if (mAnimationCurrentStep == mAnimationLongTotalSteps)
        {
            // Reset animation counter
            mAnimationCurrentStep = 0;

            // Switch state
            mState = eShowingScoreTable;
        }
    }

    // Remove the hidden floating score
    mFloatingScores.erase(
        remove_if (mFloatingScores.begin(),
                   mFloatingScores.end(),
                   std::bind<bool>(&FloatingScore::ended, _1)),
        mFloatingScores.end());

    // Remove the hiden particle systems
    mParticleSet.erase(
        remove_if (mParticleSet.begin(),
                   mParticleSet.end(),
                   std::bind<bool>(&ParticleSystem::ended, _1)),
        mParticleSet.end());
}

void GameBoard::draw()
{
    // Get mouse position
    int mX = (int) mGame -> getMouseX();
    int mY = (int) mGame -> getMouseY();

    // Draw the selector if the mouse is over a gem
    if (overGem(mX, mY) )
    {
        // Draw the selector over that gem
        mImgSelector.draw(
            241 + getCoord(mX, mY).x * 65,
            41 + getCoord(mX, mY).y * 65,
            4);
    }

    // Draw the selector if a gem has been selected
    if (mState == eGemSelected)
    {
        mImgSelector.draw(241 + mSelectedSquareFirst.x * 65,
              41 + mSelectedSquareFirst.y * 65,
              4, 1, 1, 0, 255, {0, 255, 255, 255});
    }

    // Draw the hint
    mHint.draw();

    // Draw each floating score
    std::for_each(mFloatingScores.begin(),
      mFloatingScores.end(),
      std::bind(&FloatingScore::draw, _1));

    // Draw each particle system
    std::for_each(mParticleSet.begin(),
      mParticleSet.end(),
      std::bind(&ParticleSystem::draw, _1));

    // If game has finished, draw the score table
    if (mState == eShowingScoreTable)
    {
        scoreTable -> draw(241 + (65 * 8) / 2 - 150  , 105, 3);
    }


    // On to the gem drawing procedure. Let's have a pointer to the image of each gem
    GoSDL::Image * img = NULL;

    // Top left position of the board
    int posX = 241;
    int posY = 41;

    for(int i = 0; i < 8; ++i)
    {
        for(int j = 0; j < 8; ++j)
        {
            // Reset the pointer
            img = NULL;

            // Check the type of each square and
            // save the proper image in the img pointer
            switch(mBoard.squares[i][j])
            {
                case sqWhite:
                img = &mImgWhite;
                break;

                case sqRed:
                img = &mImgRed;
                break;

                case sqPurple:
                img = &mImgPurple;
                break;

                case sqOrange:
                img = &mImgOrange;
                break;

                case sqGreen:
                img = &mImgGreen;
                break;

                case sqYellow:
                img = &mImgYellow;
                break;

                case sqBlue:
                img = &mImgBlue;
                break;

                case sqEmpty:
                img = NULL;
                break;
            }

            if (img == NULL)
            {
                continue;
            }

            float imgX = posX + i * 65;
            float imgY = posY + j * 65;
            float imgAlpha = 255;

            // When the board is first appearing, all the gems are falling
            if (mState == eBoardAppearing)
            {
                imgY = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posY + mBoard.squares[i][j].origY * 65),
                        float(mBoard.squares[i][j].destY * 65),
                        float(mAnimationLongTotalSteps));
            }

            // When two correct gems have been selected, they switch positions
            else if (mState == eGemSwitching)
            {
                // If the current gem is the first selected square
                if (mSelectedSquareFirst.equals(i,j))
                {
                    imgX = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posX + i * 65),
                        float((mSelectedSquareSecond.x - mSelectedSquareFirst.x) * 65),
                        float(mAnimationShortTotalSteps));

                    imgY = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posY + j * 65),
                        float((mSelectedSquareSecond.y - mSelectedSquareFirst.y) * 65),
                        float(mAnimationShortTotalSteps));
                }

                // If the current gem is the second selected square
                else if (mSelectedSquareSecond.equals(i,j))
                {
                    imgX = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posX + i * 65),
                        float((mSelectedSquareFirst.x - mSelectedSquareSecond.x) * 65),
                        float(mAnimationShortTotalSteps));

                    imgY = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posY + j * 65),
                        float((mSelectedSquareFirst.y - mSelectedSquareSecond.y) * 65),
                        float(mAnimationShortTotalSteps));
                }
            }

            // When the two selected gems have switched, the matched gems disappear
            else if (mState == eGemDisappearing)
            {
                if (mGroupedSquares.matched(Coord(i, j)))
                {
                    imgAlpha = 255 * (1 -(float)mAnimationCurrentStep/mAnimationShortTotalSteps);
                }
            }

            // When matched gems have disappeared, spaces in the board must be filled
            else if (mState == eBoardFilling)
            {
                if (mBoard.squares[i][j].mustFall)
                {
                    imgY = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posY + mBoard.squares[i][j].origY * 65),
                        float(mBoard.squares[i][j].destY * 65),
                        float(mAnimationShortTotalSteps));
                }
            }

            // When there are no more matching movements, the board disappears
            else if (mState == eBoardDisappearing || mState == eTimeFinished)
            {
                imgY = Animacion::easeInQuad(
                        float(mAnimationCurrentStep),
                        float(posY + mBoard.squares[i][j].origY * 65),
                        float(mBoard.squares[i][j].destY * 65),
                        float(mAnimationLongTotalSteps));
            }

            else if (mState == eShowingScoreTable)
            {
                continue;
            }

            img->draw(imgX, imgY, 3, 1, 1, 0, imgAlpha);
        }


    }
}

void GameBoard::mouseButtonDown(int mouseX, int mouseY)
{
    // A gem was clicked
    if (overGem(mouseX, mouseY))
    {
        mGameBoardSounds.playSoundSelect();

        // If there's no gem selected
        if (mState == eSteady)
        {
            mState = eGemSelected;

            mSelectedSquareFirst.x = getCoord(mouseX, mouseY).x;
            mSelectedSquareFirst.y = getCoord(mouseX, mouseY).y;
        }

        // If there was previous a gem selected
        else if (mState == eGemSelected)
        {
            // If the newly clicked gem is a winning one
            if (checkClickedSquare(mouseX, mouseY))
            {
                // Switch the state and reset the animation
                mState = eGemSwitching;
                mAnimationCurrentStep = 0;
            }
            else
            {
                mState = eSteady;
                mSelectedSquareFirst.x = -1;
                mSelectedSquareFirst.y = -1;
            }
        }

    } //*/
}

void GameBoard::mouseButtonUp(int mX, int mY)
{
    if (mState == eGemSelected)
    {
        // Get the coordinates where the mouse was released
        Coord res = getCoord(mX, mY);

        // If the square is different from the previously selected one
        if (res != mSelectedSquareFirst && checkClickedSquare(mX, mY))
        {
            // Switch the state and reset the animation
            mState = eGemSwitching;
            mAnimationCurrentStep = 0;
        }
    }
}

void GameBoard::showHint ()
{
    // Get possible hint locations
    vector<Coord> hintLocations = mBoard.solutions();

    // Start hint animation
    mHint.showHint(hintLocations[0]);
}

void GameBoard::createFloatingScores()
{
    // For each match in the group of matched squares
    for (Match & m : mGroupedSquares)
    {
        // Create a new floating score image
        mFloatingScores.emplace_back(FloatingScore(mGame,
           m.size() * 5 * mMultiplier,
           m.midSquare().x,
           m.midSquare().y, 80));

        // Create a new particle system for it to appear over the square
        for(size_t i = 0, s = m.size(); i < s; ++i)
        {
            mParticleSet.emplace_back(ParticleSystem(mGame,
                50, 50,
                241 + m[i].x * 65 + 32,
                41 + m[i].y * 65 + 32, 60, 0.5));

        }

        mStateGame->increaseScore(m.size() * 5 * mMultiplier);
    }
}

void GameBoard::playMatchSound()
{
    if (mMultiplier == 1)
    {
        mGameBoardSounds.playSoundMatch1();
    }
    else if (mMultiplier == 2)
    {
        mGameBoardSounds.playSoundMatch2();
    }
    else
    {
        mGameBoardSounds.playSoundMatch3();
    }
}

/// Tests if the mouse is over a gem
bool GameBoard::overGem (int mX, int mY)
{
    return (mX > 241 && mX < 241 + 65 * 8 &&
        mY > 41 && mY < 41 + 65 * 8);
}

/// Returns the coords of the gem the mouse is over
Coord GameBoard::getCoord (int mX, int mY)
{
    return Coord((mX - 241) / 65 ,
       (mY - 41) / 65 );
}

bool GameBoard::checkClickedSquare(int mX, int mY)
{
    // Get the selected square
    mSelectedSquareSecond = getCoord(mX, mY);

    // If it's a contiguous square
    if (abs(mSelectedSquareFirst.x - mSelectedSquareSecond.x) +
        abs(mSelectedSquareFirst.y - mSelectedSquareSecond.y) == 1)
    {
        // Create a temporal board with the movement already performed
        Board temporal = mBoard;
        temporal.swap(mSelectedSquareFirst.x, mSelectedSquareFirst.y,
                      mSelectedSquareSecond.x, mSelectedSquareSecond.y);

        // Check if there are grouped gems in that new board
        mGroupedSquares = temporal.check();

        // If there are winning movements
        if (! mGroupedSquares.empty())
        {
            return true;
        }
    }

    return false;
}