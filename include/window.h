#ifndef _WINDOW_H_
#define _WINDOW_H_

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_mixer.h>

#include <string>

#include "button.h"
#include "DrawingQueue.h"


namespace GoSDL {

    class Window {

    private:

        /// Window width
        unsigned mWidth;

        // Window height
        unsigned mHeight;

        // Window's caption
        std::string mCaption;

        // Whether the game runs in fullscreen or not
        bool mFullscreen;

        // Running flag
        bool mShouldRun;

        // Time interval between frames, in milliseconds
        double mUpdateInterval;

        // Ticks recorded in last frame
        Uint32 mLastTicks;

        // Main rendering window
        SDL_Window * mWindow = NULL;

        // Main renderer
        SDL_Renderer * mRenderer = NULL;

        // Rendering queue
        DrawingQueue mDrawingQueue;



    public:
        Window (unsigned width, unsigned height, std::string caption, bool fullscreen = false, double updateInterval = 16.666666);
        ~Window();

        void show();
        void close();

        virtual void update() = 0;
        virtual void draw() = 0;

        void enqueueDraw(SDL_Texture * texture, SDL_Rect destRect, double angle, float z, Uint8 alpha, SDL_Color color);

        virtual void buttonDown(SDL_Keycode button) { }
        virtual void buttonUp(SDL_Keycode button) { }
        virtual void mouseButtonDown(Uint8 button) { }
        virtual void mouseButtonUp(Uint8 button) { }

        int getMouseX();
        int getMouseY();

        SDL_Renderer * getRenderer() { return mRenderer; }
    };

}

#endif /* _WINDOW_H_ */
