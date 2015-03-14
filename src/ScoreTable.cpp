#include "ScoreTable.h"
#include "inter.h"

#include "log.h"
#include "go_font.h"
#include "Game.h"

#include <fstream>
#include <unistd.h>
#include <pwd.h>

using namespace std;

ScoreTable::ScoreTable(Game * p, int score) : mGame(p)
{
    int lastScore;

    // Get user's HOME dir
    const char *homedir;

    if ((homedir = getenv("HOME")) == NULL)
    {
        homedir = getpwuid(getuid())->pw_dir;
    }

    // Build the full path to the config file: $HOME/.freegemas
    std::string fullScoreFilePath(homedir);
    fullScoreFilePath += "/.freegemas";

    // Open the file
    fstream scoreFile (fullScoreFilePath.c_str(), fstream::in);

    // Read last high score
    if (!scoreFile)
    {
        lastScore = 0;
    }

    else
    {
        scoreFile >> lastScore;
    }

    scoreFile.close();

    // Reopen the file to save the new highest score
    if (lastScore < score)
    {
        scoreFile.open (fullScoreFilePath.c_str(), fstream::out);

        if (scoreFile)
            scoreFile << std::to_string(score);
    }

    scoreBoardWidth = 300;

    // Load necessary fonts
    GoSDL::Font fntH1, fntH2, fntLcdBig, fntLcdSmall;;
    fntH1.setAll(mGame, "media/fuenteMenu.ttf", 60);
    fntH2.setAll(mGame, "media/fuenteNormal.ttf", 35);
    fntLcdBig.setAll(mGame, "media/fuentelcd.ttf", 72);
    fntLcdSmall.setAll(mGame, "media/fuentelcd.ttf", 36);

    // Cache-render texts
    mRenderedHeader = fntH1.renderText(_("GAME OVER"));
    mRenderedScore = fntLcdBig.renderText(std::to_string(score));
    mRenderedLastScore = fntH2.renderText(_("Latest high score: ") + std::to_string(lastScore));
}

void ScoreTable::draw(int x, int y, int z)
{
    // Get the center
    int center = x + scoreBoardWidth / 2;

    // Draw the title and its shadow
    mRenderedHeader.draw(center - mRenderedHeader.getWidth() / 2, y, z);
    mRenderedHeader.draw(center - mRenderedHeader.getWidth() / 2 + 1, y + 3, z - 1,
        1, 1, 0, 128, {0, 0, 0, 255});

    // Draw the score and its shadow
    mRenderedScore.draw(center - mRenderedScore.getWidth() / 2, y + 67 + 10, z);
    mRenderedScore.draw(center - mRenderedScore.getWidth() / 2 + 1, y + 70 + 10, z - 1,
        1, 1, 0, 128, {0, 0, 0, 255});

    // Draw the score and its shadow
    mRenderedLastScore.draw(center - mRenderedLastScore.getWidth() / 2, y + 67 + 80, z);
    mRenderedLastScore.draw(center - mRenderedLastScore.getWidth() / 2 + 1, y + 70 + 80, z - 1,
        1, 1, 0, 128, {0, 0, 0, 255});
}