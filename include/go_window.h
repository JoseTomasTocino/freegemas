#ifndef _WINDOW_H_
#define _WINDOW_H_

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_mixer.h>

#include <string>

#include "go_drawingqueue.h"
#include "OptionsManager.h"


namespace GoSDL {

    class Window {

    public:
        /**
         * @brief Creates a new SDL window with the given dimensions and parameters
         *
         * @param width Width of the window
         * @param height Height of the window
         * @param caption Title of the window
         * @param fullscreen Whether it should be displayed in fullscreen
         * @param updateInterval Update interval in milliseconds, the inverse of fps
         */
        Window (unsigned width, unsigned height,
                std::string caption,
                Uint32 updateInterval = 17);

        /**
         * @brief Destructor of the window
         * @details Internally it destroys the renderer and quits SDL subsystems.
         */
        ~Window();

        /**
         * @brief Shows the window and starts the game loop
         * @details This method will run as long as the game, until a quit event
         *     arises.
         */
        void show();

        /**
         * @brief Closes the window
         * @details Internally, it sets the mShouldRun flag to false to quit the
         *     game loop
         */
        void close();

        /**
         * @brief This is where the logic should go.
         * @details It gets called on every frame and has to be overloaded.
         */
        virtual void update() = 0;

        /**
         * @brief This is where the code regarding graphics should go.
         * @details It gets called on every frame and has to be overloaded.
         */
        virtual void draw() = 0;

        /**
         * @brief Event for key down events
         * @details It receives the SDL_Keycode of the pressed button.
         */
        virtual void buttonDown(SDL_Keycode) { }

        /**
         * @brief Event for the key up events
         * @details It receives the SDL_Keycode of the released button.
         */
        virtual void buttonUp(SDL_Keycode) { }

        /**
         * @brief Event for the mouse button press events.
         * @details It receives the pressed mouse button.
         */
        virtual void mouseButtonDown(Uint8) { }

        /**
         * @brief Event for the mouse button release events
         * @details It receives the released mouse button
         */
        virtual void mouseButtonUp(Uint8) { }

        /**

         * @brief Event for the game controller button press events
         * @details It receives the pressed game controller button
         */
        virtual void controllerButtonDown(Uint8) { }

        /**
         * @brief Returns if the mouse is in use
         */
        int getMouseActive() { return mMouseActive; }

        /**
         * @brief Returns the horizontal position of the mouse
         */
        int getMouseX() { return mMouseX; }

        /**
         * @brief Returns the vertical position of the mouse
         */
        int getMouseY() { return mMouseY; }

        /**
         * @brief Allows setting the fullscreen mode
         */
        void setFullscreen(bool value);

    private:
        friend class Image;
        friend class Font;

        inline SDL_Renderer * getRenderer() { return mRenderer; }
        void enqueueDraw(SDL_Texture * texture, SDL_Rect destRect, double angle, float z, Uint8 alpha, SDL_Color color);

        // Called when a game controller is connected
        void openGameController(Sint32);

        // Called when a game controller is disconnected
        void closeDisconnectedGameControllers();

        // Called when closing the game
        void closeAllGameControllers();

        /// Running flag
        bool mShouldRun;

        /// Time interval between frames, in milliseconds
        Uint32 mUpdateInterval;

        /// Ticks recorded in last frame
        Uint32 mLastTicks;

        // Whether the mouse is in use
        bool mMouseActive = false;

        /// Mouse coordinates
        int mMouseX, mMouseY;

        /// Main rendering window
        SDL_Window * mWindow = NULL;

        /// Main renderer
        SDL_Renderer * mRenderer = NULL;

        /// Rendering queue
        DrawingQueue mDrawingQueue;

        // Options manager to get full screen setting
        OptionsManager mOptions;

        // List of connected game controllers
        std::vector<SDL_GameController*> gameControllers;
    };

}

#endif /* _WINDOW_H_ */
