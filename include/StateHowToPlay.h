#ifndef _STATEHOWTOPLAY_H_
#define _STATEHOWTOPLAY_H_

#include <memory>

#include "State.h"
#include "go_image.h"

class TextBlock;
class Game;

class StateHowtoplay : public State {
public:

    StateHowtoplay(Game * p);

    void update();
    void draw();

    void buttonDown (SDL_Keycode button);
    void mouseButtonDown (Uint8 button);

    ~StateHowtoplay();

private:
    GoSDL::Image mImgBackground;

    GoSDL::Image mImgTitle;
    GoSDL::Image mImgTitleShadow;
    GoSDL::Image mImgSubtitle;
    GoSDL::Image mImgSubtitleShadow;

    GoSDL::Image mImgBodyText;
    GoSDL::Image mImgBodyTextShadow;
};

#endif /* _STATEHOWTOPLAY_H_ */
