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

    mImgTitle = fontTitle.renderTextWithShadow(_("How to play"), {255, 255, 255, 255}, 1, 2, {0, 0, 0, 128});

    // Build the subtitle text
    GoSDL::Font fontSubtitle;

    fontSubtitle.setWindow(p);
    fontSubtitle.setPathAndSize("media/fuenteMenu.ttf", 23);

    std::string subtitleText = _("Press any button to go back");

    mImgSubtitle = fontSubtitle.renderTextWithShadow(subtitleText.c_str(), {255, 255, 255, 255}, 1, 2, {0, 0, 0, 128});

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

    mImgBodyText = fontText.renderBlockWithShadow(bodyText.c_str(), {255, 255, 255, 255}, 450, 1, 2, {0, 0, 0, 128});
}

void StateHowtoplay::update() { }

void StateHowtoplay::draw()
{
    mImgBackground.draw(0,0,0);

    mImgTitle.draw(300 + 470 / 2 - mImgTitle.getWidth() / 2, 20, 1);

    mImgSubtitle.draw(30, 550, 1);

    mImgBodyText.draw(310, 110, 1);
}

void StateHowtoplay::buttonDown(SDL_Keycode)
{
        mGame -> changeState("stateMainMenu");
}

void StateHowtoplay::controllerButtonDown(Uint8)
{
    mGame -> changeState("stateMainMenu");
}

void StateHowtoplay::mouseButtonDown(Uint8)
{
        mGame -> changeState("stateMainMenu");
}

StateHowtoplay::~StateHowtoplay()
{
    lDEBUG << Log::DES("StateHowtoPlay");
}
