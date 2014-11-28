#ifndef GAME_INDICATORS_H
#define GAME_INDICATORS_H

#include "font.h"
#include "image.h"
#include "music.h"
#include "baseButton.h"

#include <string>

class Game;
class StateGame;

class GameIndicators
{
public:
    GameIndicators();

    void setGame(Game *, StateGame *);

    void init();

    void updateScore (int score);
    void updateTime (double time);
    void update();

    void draw();
    void click(int, int);

private:
    Game * mGame;
    StateGame * mStateGame;

    int mScore, mLastScore;

    double mRemainingTime;

    /// String with the remaining time
    std::string mTxtTime;

    /// Score in previous iteration of game loop
    std::string mTxtLastTime;

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