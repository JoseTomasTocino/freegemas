#include "ScoreTable.h"
#include "inter.h"

#include "log.h"
#include "go_font.h"
#include "Game.h"

#include <fstream>

#ifdef _WIN32
    #include <io.h>
    #include <process.h>
#else
    #include <pwd.h>
    #include <unistd.h>
#endif

using namespace std;

ScoreTable::ScoreTable(Game * p, int score, string gameMode) : mGame(p)
{
    options.loadResources();

    int lastScore;
    if (gameMode == "stateGameTimetrial") {
        lastScore = options.getHighscoreTimetrial();
        if (lastScore < score) {
            options.setHighscoreTimetrial(score);
        }
    } else if (gameMode == "stateGameEndless") {
        lastScore = options.getHighscoreEndless();
        if (lastScore < score) {
            options.setHighscoreEndless(score);
        }
    }

    scoreBoardWidth = 300;

    // Load necessary fonts
    GoSDL::Font fntH1, fntH2, fntLcdBig, fntLcdSmall;;
    fntH1.setAll(mGame, "media/fuenteMenu.ttf", 60);
    fntH2.setAll(mGame, "media/fuenteNormal.ttf", 35);
    fntLcdBig.setAll(mGame, "media/fuentelcd.ttf", 72);
    fntLcdSmall.setAll(mGame, "media/fuentelcd.ttf", 36);

    // Cache-render texts
    mRenderedHeader = fntH1.renderTextWithShadow(_("GAME OVER"), {255, 255, 255, 255}, 1, 3, {0, 0, 0, 128});
    mRenderedScore = fntLcdBig.renderTextWithShadow(std::to_string(score), {255, 255, 255, 255}, 1, 3, {0, 0, 0, 128});
    mRenderedLastScore = fntH2.renderTextWithShadow(_("Latest high score: ") + std::to_string(lastScore), {255, 255, 255, 255}, 1, 3, {0, 0, 0, 128});
}

void ScoreTable::draw(int x, int y, int z)
{
    // Get the center
    int center = x + scoreBoardWidth / 2;

    // Draw the title and its shadow
    mRenderedHeader.draw(center - mRenderedHeader.getWidth() / 2, y, z);

    // Draw the score and its shadow
    mRenderedScore.draw(center - mRenderedScore.getWidth() / 2, y + 67 + 10, z);

    // Draw the score and its shadow
    mRenderedLastScore.draw(center - mRenderedLastScore.getWidth() / 2, y + 67 + 80, z);
}
