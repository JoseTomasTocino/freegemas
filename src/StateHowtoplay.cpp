#include "StateHowToPlay.h"

#include "Game.h"
#include "inter.h"

#include "go_font.h"

StateHowtoplay::StateHowtoplay(Game * p) : State(p)
{
    lDEBUG << Log::CON("StateHowtoPlay");

    mImgBackground.setWindowAndPath(p, "media/howtoScreen.png");

    // Build the title text
    GoSDL::Font fontTitle;

    fontTitle.setWindow(p);
    fontTitle.setPathAndSize("media/fuenteMenu.ttf", 48);

    mImgTitle = fontTitle.renderText(_("How to play"), {255, 255, 255, 255});
    mImgTitleShadow = fontTitle.renderText(_("How to play"), {0, 0, 0, 255});

    // Build the subtitle text
    GoSDL::Font fontSubtitle;

    fontSubtitle.setWindow(p);
    fontSubtitle.setPathAndSize("media/fuenteMenu.ttf", 23);

    mImgSubtitle = fontSubtitle.renderText(_("Press escape to go back"), {255, 255, 255, 255});
    mImgSubtitleShadow = fontSubtitle.renderText(_("Press escape to go back"), {0, 0, 0, 255});

    // Build the main text
    GoSDL::Font fontText;

    fontText.setWindow(p);
    fontText.setPathAndSize("media/fuenteNormal.ttf", 28);

    string bodyText = "";

    bodyText += _("The objective of the game is to swap one gem with an adjacent gem to form a horizontal or vertical chain of three or more gems.");
    bodyText += "\n\n";
    bodyText += _("Click the first gem and then click the gem you want to swap it with. If the movement is correct, they will swap and the chained gems will disappear.");
    bodyText += "\n\n";
    bodyText += _("Bonus points are given when more than three identical gems are formed. Sometimes chain reactions, called cascades, are triggered, where chains are formed by the falling gems. Cascades are awarded with bonus points.");

    mImgBodyText = fontText.renderBlock(bodyText.c_str(), {255, 255, 255, 255}, 450);
    mImgBodyTextShadow = fontText.renderBlock(bodyText.c_str(), {0, 0, 0, 255}, 450);
}

void StateHowtoplay::update() { }

void StateHowtoplay::draw()
{
    mImgBackground.draw(0,0,0);

    mImgTitle.draw(300 + 470 / 2 - mImgTitle.getWidth() / 2, 20, 1);
    mImgTitleShadow.draw(301 + 470 / 2 - mImgTitle.getWidth() / 2, 22, 0.9, 1, 1, 0, 128);

    mImgSubtitle.draw(30, 550, 1);
    mImgSubtitleShadow.draw(30 + 1, 550 + 2, 0.9, 1, 1, 0, 128);

    mImgBodyText.draw(310, 110, 1);
    mImgBodyTextShadow.draw(311, 112, 0.9,  1, 1, 0, 128);
}

void StateHowtoplay::buttonDown(SDL_Keycode button)
{
    if (button == SDLK_ESCAPE)
    {
        mGame -> changeState("stateMainMenu");
    }
}

void StateHowtoplay::mouseButtonDown(Uint8 button)
{
    if (button == SDL_BUTTON_LEFT)
    {
        mGame -> changeState("stateMainMenu");
    }
}

StateHowtoplay::~StateHowtoplay()
{
    lDEBUG << Log::DES("StateHowtoPlay");
}
