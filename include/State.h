#ifndef _STATE_H_
#define _STATE_H_

#include <iostream>
#include <SDL.h>

#include "log.h"

using namespace std;

class Game;

/**
 * @class State
 *
 * @brief Base clase for the game states.
 *
 * This abstract class holds the methods that the main class (Game) will
 * call. Each state should implement these methods as needed.
 *
*/

class State{
protected:
    /**
     * @brief Reference to the game's main class
     *
     * It's used when we have to switch states (calling #Game::changeState(),
     * access the graphics system (using Game::graphics()), etc.
    **/
    Game * mGame;

public:
    /**
     * Default constructor. It receives a pointer to the game's main class.
     *
     */
    State(Game * p);

    /// Control logic happens here
    virtual void update() = 0;

    /// Drawing operations happen here
    virtual void draw() = 0;

    /// Triggers when a key is pressed
    virtual void buttonDown(SDL_Keycode){ }

    /// Triggers when a key is released
    virtual void buttonUp(SDL_Keycode){ }

    virtual void mouseButtonDown(Uint8) { }

    virtual void mouseButtonUp(Uint8) { }

    /// Default destructor
    virtual ~State();
};

#endif /* _STATE_H_ */
