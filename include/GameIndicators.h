#ifndef GAME_INDICATORS_H
#define GAME_INDICATORS_H

#include "go_font.h"
#include "go_image.h"
#include "go_music.h"

#include "BaseButton.h"

#include <string>

class Game;
class StateGame;

class GameIndicators
{
public:
    GameIndicators();

    void setGame(Game *, StateGame *);

    void loadResources();

    /// Returns the current score
    int getScore();

    /// Sets the score to the given amount
    void setScore (int score);

    /// Increases the score by the given amount
    void increaseScore (int amount);

    /// Updates the remaining time, the argument is given in seconds
    void updateTime (double time);

    void draw();
    void click(int, int);

private:

    /// Regenerates the texture for the score, if necessary
    void regenerateScoreTexture();

    Game * mGame;
    StateGame * mStateGame;

    /// Current score
    int mScore = 0;

    /// Score in the previous frame
    int mScorePrevious = -1;

    /// Remaining time, in seconds
    double mRemainingTime = 0;

    /// Remaining time in the previous frame
    double mRemainingTimePrevious = 0;

    /// Font for the timer
    GoSDL::Font mFontTime;

    /// Font for the current-score text
    GoSDL::Font mFontScore;

   // Background of the timer
    GoSDL::Image mImgTimeBackground;

    /// Background for the current-score board
    GoSDL::Image mImgScoreBackground;

    /// Image for the clock
    GoSDL::Image mImgTime;
    GoSDL::Image mImgTimeHeader;
    GoSDL::Image mImgTimeHeaderShadow;

    /// Image for the current-score
    GoSDL::Image mImgScore;
    GoSDL::Image mImgScoreHeader;
    GoSDL::Image mImgScoreHeaderShadow;

    /// @{
    /// @name Buttons of the interface
    BaseButton mHintButton;
    BaseButton mResetButton;
    BaseButton mExitButton;
    BaseButton mMusicButton;
    /// @}

    /// Game music
    GoSDL::Music sfxSong;
};

#endif