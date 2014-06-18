#ifndef _GAME_H_
#define _GAME_H_

#include <string>
#include <memory>

#include "window.h"
#include "image.h"


class State;

class Game : public GoSDL::Window{

public:
    Game ();

    void update();

    void draw();

    void buttonDown(SDL_Keycode button);
    void buttonUp(SDL_Keycode button);
    void mouseButtonDown(Uint8 button);
    void mouseButtonUp(Uint8 button);

    void changeState(std::string S);

    ~Game();

private:

    std::shared_ptr<State> mCurrentState = nullptr;
    std::string mCurrentStateString;

    GoSDL::Image mMouseCursor;

};

#endif /* _GAME_H_ */
