#include "stateGame.h"
#include "log.h"
#include "game.h"
// #include "resManager.h"
#include "inter.h"
#include "animation.h"

#include <cmath>
#include <algorithm>
#include <functional>

using namespace std::placeholders;

StateGame::StateGame(Game * p) : State(p)
{
    lDEBUG << Log::CON("StateGame");

    // Set the initial loading state
    mState = eLoading;

    // Load the loading screen
    mImgLoadingBanner.setWindowAndPath(p, "media/loadingBanner.png");

    // Initialize the random number generator seed
    std::srand(std::clock());
}

StateGame::~StateGame()
{
    lDEBUG << Log::DES("StateGame");
}

void StateGame::init()
{
    lDEBUG << "StateGame::init";

    mGameIndicators.setGame(mGame, this);
    mGameIndicators.init();

    initSounds();
    initImages();
    initParameters();

    // Reset the game to the initial values
    resetGame();

    // sfxSong.play();
    // sfxSong.changeVolume(0.5);
}

void StateGame::initSounds()
{
    // Sounds
    sfxMatch1.setSample("media/match1.ogg");
    sfxMatch2.setSample("media/match2.ogg");
    sfxMatch3.setSample("media/match3.ogg");
    sfxSelect.setSample("media/select.ogg");
    sfxFall.setSample("media/fall.ogg");
}

void StateGame::initImages()
{
    // Load the backgorund image
    mImgBoard.setWindowAndPath(mGame, "media/board.png");

    // Load the image for the square selector
    mImgSelector.setWindowAndPath(mGame, "media/selector.png");

    // Images for the gems
    mImgWhite.setWindowAndPath(mGame, "media/gemWhite.png");
    mImgRed.setWindowAndPath(mGame, "media/gemRed.png");
    mImgPurple.setWindowAndPath(mGame, "media/gemPurple.png");
    mImgOrange.setWindowAndPath(mGame, "media/gemOrange.png");
    mImgGreen.setWindowAndPath(mGame, "media/gemGreen.png");
    mImgYellow.setWindowAndPath(mGame, "media/gemYellow.png");
    mImgBlue.setWindowAndPath(mGame, "media/gemBlue.png");
}

void StateGame::initParameters ()
{
    // Initial animation state
    mAnimationCurrentStep = 0;

    // Steps for short animations
    mAnimationTotalSteps = 17;

    // Steps for long animations
    mAnimationInitialSteps = 50;

    // Steps for the hint animation
    mHintAnimationTotalSteps = 50;

    // Reset the hint flag
    mShowingHint = -1;

    // Initial score mMultiplier
    mMultiplier = 1;
}

void StateGame::update()
{
    /*
      Before doing anything else, we have to show, at least once, the loading
      screen. After the first draw event, we'll jump to the eFirstFlip state, where
      init() will be called and the resources will start to load
    */

    if (mState == eLoading)
    {
        return;
    }

    if (mState == eFirstFlip)
    {
        // Call init to start loading resources
        init();

        // Switch to the main game state
        mState = eInicialGemas;

        // Then stop computing the rest of the logic
        return;
    }


    // Compute the remaining time
    double remainingTime = (mTimeStart - SDL_GetTicks()) / 1000;

    // Update UI
    mGameIndicators.updateScore(mScore);
    mGameIndicators.updateTime(remainingTime);
    mGameIndicators.update();

    // If there's no time left and we're not in a final state
    if (remainingTime < 0 && mState != eTimeFinished && mState != eShowingScoreTable)
    {
        // End the game
        mState = eTimeFinished;

        // Take the gems out of the screen
        placeGemsOutScreen();
    }

    // Remove the hidden floating score
    mFloatingScores.erase(remove_if (mFloatingScores.begin(), mFloatingScores.end(),
       std::bind<bool>(&FloatingScore::ended, _1)), mFloatingScores.end());

    // Remove the hiden particle systems
    mParticleSet.erase(remove_if (mParticleSet.begin(),
      mParticleSet.end(),
      std::bind<bool>(&ParticleSystem::ended, _1)),
    mParticleSet.end());

    // Initial game state
    if (mState == eInicialGemas)
    {
        // If animation ended
        if (++mAnimationCurrentStep == mAnimationInitialSteps)
        {
            // Switch to next mState (waiting for user input)
            mState = eEspera;
            mBoard.endAnimations();

            // reset animation step counter
            mAnimationCurrentStep = 0;
        }
    }

    // In the waiting mState, the mMultiplier must be zero
    else if (mState == eEspera)
    {
        mMultiplier = 0;
    }

    // In this mState, the pair of selected gems are swapping
    else if (mState == eGemasCambiando)
    {
        // When animation ends
        if (++mAnimationCurrentStep == mAnimationTotalSteps)
        {
            // Switch to the next mState (gems start to disappear)
            mState = eGemasDesapareciendo;

            // Swap the gems in the board
            mBoard.swap(mSelectedSquareFirst.x, mSelectedSquareFirst.y,
                mSelectedSquareSecond.x, mSelectedSquareSecond.y);

            // Increase the mMultiplier
            ++mMultiplier;

            // Play matching sound
            playMatchSound();

            // Create floating scores for the matching group
            createFloatingScores();

            // Reset animation step counter
            mAnimationCurrentStep = 0;
        }
    }

    // In this mState, the swapping gems are fading
    else if (mState == eGemasDesapareciendo)
    {
        // When animation ends
        if (mAnimationCurrentStep++ == mAnimationTotalSteps){

            // Switch to the next mState (new gems fall to their position)
            mState = eGemasNuevasCayendo;

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

            // Apply changes to the board...
            mBoard.applyFall();

            // Fill empty spaces
            mBoard.fillSpaces();

            // Reset animation step counter
            mAnimationCurrentStep = 0;
        }
    }

    // In this mState, new gems are falling
    else if (mState == eGemasNuevasCayendo)
    {
        // When animation ends
        if (mAnimationCurrentStep++ == mAnimationTotalSteps)
        {
            // Play the fall sound fx
            sfxFall.play(0.3);

            // Switch to the next mState (waiting mState)
            mState = eEspera;

            // Reset animation counter
            mAnimationCurrentStep = 0;

            // Reset animation variables
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
                mState = eGemasDesapareciendo;
            }

            // If there are neither current solutions nor possible future solutions
            else if (mBoard.solutions().empty())
            {
                // Make the board disappear
                mState = eDesapareceBoard;

                placeGemsOutScreen();
            }
        }
    }

    // In this mState, the board is disappearing because there were no possible movements
    else if (mState == eDesapareceBoard)
    {
        // When animation ends
        if (++mAnimationCurrentStep == mAnimationInitialSteps)
        {
            // Switch to the initial mState
            mState = eInicialGemas;

            // Generate a brand new board
            mBoard.generate();

            // Reset animation counter
            mAnimationCurrentStep = 0;
        }
    }

    // In this mState, the time has finished, so we need to create a ScoreBoard
    else if (mState == eTimeFinished)
    {
        // When animation ends
        if (++mAnimationCurrentStep == mAnimationInitialSteps)
        {
            // Create a new score table
            scoreTable.reset(new ScoreTable(mGame, mScore));

            // Switch to the following mState
            mState = eShowingScoreTable;

            // Reset animation counter
            mAnimationCurrentStep = 0;
        }
    }

    // Whenever a hint is being shown, decrease its controlling variable
    if (mShowingHint != -1)
    {
        mShowingHint --;
    }

    //*/
}


void StateGame::draw()
{
    // If we're still loading resources, just show the loading screen
    if (mState == eLoading || mState == eFirstFlip)
    {
        mState = eFirstFlip;
        mImgLoadingBanner.draw(156, 200, 2);

        return;
    }

    // Draw the background image
    mImgBoard.draw(0,0,1);

    // Draw the UI
    mGameIndicators.draw();

    // Draw each score little messages
    std::for_each(mFloatingScores.begin(),
      mFloatingScores.end(),
      std::bind(&FloatingScore::draw, _1));

    // // Draw each particle system
    std::for_each(mParticleSet.begin(),
      mParticleSet.end(),
      std::bind(&ParticleSystem::draw, _1));


    // Starting position for the squares
    int posX = 241;
    int posY = 41;

    // Draw the squares only if we're not showing the score table
    if (mState != eShowingScoreTable){

        // Generic pointer for drawing the squares
        GoSDL::Image * img = NULL;

        // Go through all of the squares
        for(int i = 0; i < 8; ++i)
        {
            for(int j = 0; j < 8; ++j)
            {
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
                    lDEBUG << "Square is empty:" << i << " " << j;
                    img = NULL;
                    break;
                } // fin switch

                // Now, if img is not NULL (there's something to draw)
                if (img != NULL)
                {
                    // Default positions
                    float imgX = posX + i * 65;
                    float imgY = posY + j * 65;
                    float imgAlpha = 255;

                    // In the initial state, the gems fall vertically
                    // decreasing its speed
                    if (mState == eInicialGemas)
                    {
                        imgY = Animacion::easeOutQuad(
                            float(mAnimationCurrentStep),
                            float(posY + mBoard.squares[i][j].origY * 65),
                            float(mBoard.squares[i][j].destY * 65),
                            float(mAnimationInitialSteps));
                    }

                    // In the ending states, gems fall vertically,
                    // increasing their speed
                    else if (mState == eDesapareceBoard || mState == eTimeFinished)
                    {
                        imgY = Animacion::easeInQuad(
                            float(mAnimationCurrentStep),
                            float(posY + mBoard.squares[i][j].origY * 65),
                            float(mBoard.squares[i][j].destY * 65),
                            float(mAnimationInitialSteps));
                    }

                    else if ((mState == eEspera ||
                       mState == eGemaMarcada ||
                       mState == eGemasNuevasCayendo)
                        &&
                        mBoard.squares[i][j].mustFall)
                    {
                        imgY = Animacion::easeOutQuad(
                            float(mAnimationCurrentStep),
                            float(posY + mBoard.squares[i][j].origY * 65),
                            float(mBoard.squares[i][j].destY * 65),
                            float(mAnimationTotalSteps));
                    }

                    // When two gems are switching
                    else if (mState == eGemasCambiando)
                    {
                        if (i == mSelectedSquareFirst.x &&
                         j == mSelectedSquareFirst.y){

                            imgX = Animacion::easeOutQuad(
                                float(mAnimationCurrentStep),
                                float(posX + i * 65),
                                float((mSelectedSquareSecond.x - mSelectedSquareFirst.x) * 65),
                                float(mAnimationTotalSteps));

                        imgY = Animacion::easeOutQuad(
                            float(mAnimationCurrentStep),
                            float(posY + j * 65),
                            float((mSelectedSquareSecond.y - mSelectedSquareFirst.y) * 65),
                            float(mAnimationTotalSteps));

                    }

                    else if (i == mSelectedSquareSecond.x &&
                        j == mSelectedSquareSecond.y){

                        imgX = Animacion::easeOutQuad(
                            float(mAnimationCurrentStep),
                            float(posX + i * 65),
                            float((mSelectedSquareFirst.x - mSelectedSquareSecond.x) * 65),
                            float(mAnimationTotalSteps));

                    imgY = Animacion::easeOutQuad(
                        float(mAnimationCurrentStep),
                        float(posY + j * 65),
                        float((mSelectedSquareFirst.y - mSelectedSquareSecond.y) * 65),
                        float(mAnimationTotalSteps));

                }
            }

            else if (mState == eGemasDesapareciendo){
                // Desaparición de las gemas ganadoras

                if (mGroupedSquares.matched(coord(i,j))){

                    imgAlpha = int(255 * (1 -(float)mAnimationCurrentStep/mAnimationTotalSteps));
                }
            }

                    // Finally draw the image
            img -> draw(imgX, imgY, 3,  1, 1, 0, imgAlpha);

                } // Fin if (img != NULL)

                img = NULL;
            }
        }

        // Get the mouse position
        int mX = (int) mGame -> getMouseX();
        int mY = (int) mGame -> getMouseY();

        // If the mouse is over a gem
        if (overGem(mX, mY) ){

            // Draw the selector over that gem
            mImgSelector.draw( 241 + getCoord(mX, mY).x * 65,
               41 + getCoord(mX, mY).y * 65,
               4);
        }

        // If a gem was previously clicked
        if (mState == eGemaMarcada){

            // Draw the tinted selector over it
            mImgSelector.draw(241 + mSelectedSquareFirst.x * 65,
              41 + mSelectedSquareFirst.y * 65,
              4, 1, 1, 0, 255, {0, 255, 255, 255});
        }

        // If a hint is being shown
        if (mShowingHint != -1){
            // Get the opacity percentage
            float p1 = (float)mShowingHint / mHintAnimationTotalSteps;

            float pX1 = 241 + mHintLocation.x * 65 - mImgSelector.getWidth() * (2 - p1) / 2 + 65 / 2;
            float pY1 = 41 + mHintLocation.y * 65 - mImgSelector.getHeight() * (2 - p1) / 2 + 65 / 2;

            mImgSelector.draw(pX1, pY1, 3,
              2 - p1, 2 - p1,
              0, p1 * 255, {0, 255, 0, 255});
        }
    }

    else
    {
        scoreTable -> draw(241 + (65 * 8) / 2 - 150  , 105, 3);
    }

    //*/
}


void StateGame::resetGame()
{
    // Reset the score
    mScore = 0;

    // Restart the time (two minutes)
    mTimeStart = SDL_GetTicks() + 2 * 60 * 1000;
    mTimeStart = SDL_GetTicks() + 5 * 1000;

    if (mState != eShowingScoreTable)
    {
        // Switch state
        mState = eDesapareceBoard;

        // Let the gems get out of the screen
        placeGemsOutScreen();
    }

    else
    {
        mState = eGemasNuevasCayendo;
    }
}

void StateGame::playMatchSound()
{
    if (mMultiplier == 1){
        sfxMatch1.play(0.25);
    }else if (mMultiplier == 2){
        sfxMatch2.play(0.25);
    }else{
        sfxMatch3.play(0.25);
    }
}

void StateGame::createFloatingScores() {

    // For each match in the group of matched squares
    for (Match & m : mGroupedSquares) {

        // Create a new floating score image
        mFloatingScores.push_back(FloatingScore(mGame,
           m.size() * 5 * mMultiplier,
           m.midSquare().x,
           m.midSquare().y, 80));

        // Create a new particle system for it to appear over the square
        for(size_t i = 0, s = m.size(); i < s; ++i) {

            mParticleSet.emplace_back(ParticleSystem(mGame,
                50, 50,
                241 + m[i].x * 65 + 32,
                41 + m[i].y * 65 + 32, 60, 0.5));

        }

        mScore += m.size() * 5 * mMultiplier;
    }

}



bool StateGame::overGem(int mX, int mY){
    return (mX > 241 && mX < 241 + 65 * 8 &&
        mY > 41 && mY < 41 + 65 * 8);
}

coord StateGame::getCoord(int mX, int mY){
    return coord((mX - 241) / 65 ,
       (mY - 41) / 65 );
}

bool StateGame::checkClickedSquare(int mX, int mY) {

    bool returnValue = false;

    // Get the selected gem
    mSelectedSquareSecond = getCoord(mX, mY);

    // Si es una gema CONTIGUA
    if (abs(mSelectedSquareFirst.x - mSelectedSquareSecond.x)
     + abs(mSelectedSquareFirst.y - mSelectedSquareSecond.y) == 1){

        // Create a temporal board with the movement already performed
        Board temporal = mBoard;
    temporal.swap(mSelectedSquareFirst.x, mSelectedSquareFirst.y,
      mSelectedSquareSecond.x, mSelectedSquareSecond.y);

        // Check if there are grouped gems in that new board
    mGroupedSquares = temporal.check();

        // If there are winning movements
    if (! mGroupedSquares.empty()){
        mState = eGemasCambiando;
        returnValue = true;
    }
}

return returnValue;

}

void StateGame::mouseButtonDown(Uint8 button)
{

    // Left mouse button was pressed
    if (button == SDL_BUTTON_LEFT) {
        mMousePressed = true;

        // Get click location
        int mouseX = mGame->getMouseX();
        int mouseY = mGame->getMouseY();

        // Inform the UI
        mGameIndicators.click(mouseX, mouseY);

        // A gem was clicked
        if (overGem(mouseX, mouseY) && mState != eShowingScoreTable)
        {
            sfxSelect.play(0.3);

            // If there's no gem selected
            if (mState == eEspera) {
                mState = eGemaMarcada;
                mSelectedSquareFirst.x = getCoord(mouseX, mouseY).x;
                mSelectedSquareFirst.y = getCoord(mouseX, mouseY).y;
            }

            // If there was a gem selected
            else if (mState == eGemaMarcada) {
                if (!checkClickedSquare(mouseX, mouseY)){
                    mSelectedSquareFirst.x = -1;
                    mSelectedSquareFirst.y = -1;
                    mState = eEspera;
                }
            }
        }
    }
}

void StateGame::mouseButtonUp(Uint8 button)
{
    if (button == SDL_BUTTON_LEFT)
    {
        mMousePressed = false;

        if (mState == eGemaMarcada)
        {
            int mX = (int) mGame -> getMouseX();
            int mY = (int) mGame -> getMouseY();

            coord res = getCoord(mX, mY);

            if (!(res == mSelectedSquareFirst))
            {
                checkClickedSquare(mX, mY);
            }
        }
    }
}


void StateGame::buttonDown (SDL_Keycode button){

    if (button == SDLK_ESCAPE)
    {
        mGame -> changeState("stateMainMenu");
    }

    else if (button == SDLK_h)
    {
        showHint();
    }
}

void StateGame::showHint() {

    // Get possible hint locations
    vector<coord> hintLocations = mBoard.solutions();
    mHintLocation = hintLocations[0];

    // Start hint animation
    mShowingHint = mHintAnimationTotalSteps;
}

void StateGame::placeGemsOutScreen(){

    for(int x = 0; x < 8; ++x)
    {
        for(int y = 0; y < 8; ++y)
        {
            mBoard.squares[x][y].mustFall = true;
            mBoard.squares[x][y].origY = y;
            mBoard.squares[x][y].destY = int(9 + rand() % 8);
        }
    }
}
