#include "GameIndicators.h"
#include "Game.h"
#include "inter.h"

#include "StateGame.h"

GameIndicators::GameIndicators() :
    mGame (NULL),
    mStateGame (NULL)
{

}

void GameIndicators::setGame (Game * g, StateGame * sg)
{
    mGame = g;
    mStateGame = sg;
}

void GameIndicators::loadResources()
{
    // Load the font for the timer
    mFontTime.setAll(mGame, "media/fuentelcd.ttf", 62);

    // Load the font for the scoreboard
    mFontScore.setAll(mGame, "media/fuentelcd.ttf", 33);

    // Font to render some headers
    GoSDL::Font tempHeaderFont;
    tempHeaderFont.setAll(mGame, "media/fuenteNormal.ttf", 37);

    mImgScoreHeader = tempHeaderFont.renderText(_("score"), {160, 169, 255, 255});
    mImgScoreHeaderShadow = tempHeaderFont.renderText(_("score"), {0,0,0, 255});

    mImgTimeHeader = tempHeaderFont.renderText(_("time left"), {160, 169, 255, 255});
    mImgTimeHeaderShadow = tempHeaderFont.renderText(_("time left"), {0,0,0, 255});

    // Load the background image for the time
    mImgTimeBackground.setWindowAndPath(mGame, "media/timeBackground.png");

    // Load the background image for the scoreboard
    mImgScoreBackground.setWindowAndPath(mGame, "media/scoreBackground.png");

    // Buttons
    mHintButton.set(mGame, _("Show hint"), "iconHint.png");
    mResetButton.set(mGame, _("Reset game"), "iconRestart.png");
    mExitButton.set(mGame, _("Exit"), "iconExit.png");
    mMusicButton.set(mGame, _("Turn off music"), "iconMusic.png");

    // Music
    sfxSong.setSample("media/music.ogg");
    sfxSong.play();
}

int GameIndicators::getScore()
{
    return mScore;
}

void GameIndicators::setScore (int score)
{
    mScore = score;

    regenerateScoreTexture();
}

void GameIndicators::increaseScore (int amount)
{
    mScore += amount;

    regenerateScoreTexture();
}

void GameIndicators::regenerateScoreTexture()
{
    // Regenerate the texture if the score has changed
    if (mScore != mScorePrevious)
    {
        mImgScore = mFontScore.renderText(std::to_string(mScore), {78, 193, 190, 255});
        mScorePrevious = mScore;
    }
}

void GameIndicators::updateTime (double time)
{
    mRemainingTime = time;

    // Only recreate the tiem string if it's changed
    if (mRemainingTime >= 0 && mRemainingTime != mRemainingTimePrevious)
    {
        int minutes = int(mRemainingTime / 60);
        int seconds = int(mRemainingTime - minutes * 60);

        std::string txtTime = std::to_string(minutes) +
            (seconds < 10 ? ":0" : ":") +
            std::to_string(seconds);

        mImgTime = mFontTime.renderText(txtTime, {78, 193, 190, 255});

        mRemainingTimePrevious = mRemainingTime;
    }
}

void GameIndicators::draw()
{
    // Vertical initial position for the buttons
    int vertButStart = 360;

    // Draw the buttons
    mHintButton.draw(17, vertButStart, 2);
    mResetButton.draw(17, vertButStart + 47, 2);
    mMusicButton.draw(17, vertButStart + 47 * 2, 2);
    mExitButton.draw(17, 538, 2);

    // Draw the score
    mImgScoreBackground.draw(17, 124, 2);
    mImgScoreHeader.draw(17 + mImgScoreBackground.getWidth() / 2 - mImgScoreHeader.getWidth() / 2, 84, 3);
    mImgScoreHeaderShadow.draw(18 + mImgScoreBackground.getWidth() / 2 - mImgScoreHeader.getWidth() / 2, 85, 2.95,  1, 1, 0, 128);
    mImgScore.draw(197 - mImgScore.getWidth(), 127, 2);

    // Draw the time
    mImgTimeBackground.draw(17, 230, 2);
    mImgTimeHeader . draw(17 + mImgTimeBackground.getWidth() / 2 - mImgTimeHeader.getWidth() / 2, 190, 3);
    mImgTimeHeaderShadow . draw(18 + mImgTimeBackground.getWidth() / 2 - mImgTimeHeader.getWidth() / 2, 191, 2, 1, 1, 0, 128);
    mImgTime.draw(190 - mImgTime.getWidth(), 232, 2);
}

void GameIndicators::click(int mouseX, int mouseY)
{
    // Exit button was clicked
    if (mExitButton.clicked(mouseX, mouseY))
    {
        mGame -> changeState("stateMainMenu");
    }

    // Hint button was clicked
    else if (mHintButton.clicked(mouseX, mouseY))
    {
        mStateGame -> showHint();
    }

    // Reset button was clicked
    else if (mResetButton.clicked(mouseX, mouseY))
    {
        mStateGame -> resetGame();
    }

    // Music button was clicked
    else if (mMusicButton.clicked(mouseX, mouseY))
    {
        if (sfxSong.isPlaying())
        {
            mMusicButton.setText(_("Turn on music"));
            sfxSong.stop();
        }
        else
        {
            mMusicButton.setText(_("Turn off music"));
            sfxSong.play();
        }
    }
}