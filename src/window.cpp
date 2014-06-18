#include "window.h"

#include <iostream>
#include <stdexcept>

using namespace std;


GoSDL::Window::Window (unsigned width, unsigned height, std::string caption, bool fullscreen, double updateInterval) :
    mWidth(width), mHeight(height), mCaption(caption), mFullscreen(fullscreen), mUpdateInterval(updateInterval) {

    mLastTicks = SDL_GetTicks();

    // Init SDL
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) {
        throw std::runtime_error(SDL_GetError());
    }

    // Set texture filtering to linear
    if (!SDL_SetHint( SDL_HINT_RENDER_SCALE_QUALITY, "1" ) ) {
        cerr << "Warning: Linear texture filtering not enabled!" << endl;
    }

    if( Mix_OpenAudio( 44100, MIX_DEFAULT_FORMAT, 2, 2048 ) < 0 ) {
        throw std::runtime_error(Mix_GetError());
    }

    // Create window
    mWindow = SDL_CreateWindow( mCaption.c_str(),
                                SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                mWidth, mHeight,
                                SDL_WINDOW_SHOWN );

    if (mWindow == NULL ) {
        throw std::runtime_error(SDL_GetError());
    }


    // Create renderer for the window
    mRenderer = SDL_CreateRenderer( mWindow, -1, SDL_RENDERER_ACCELERATED );

    if (mRenderer == NULL ) {
        throw std::runtime_error(SDL_GetError());
    }

    // Initialize renderer color
    SDL_SetRenderDrawColor( mRenderer, 0xFF, 0xFF, 0xFF, 0xFF );

    // Initialize PNG loading
    int imgFlags = IMG_INIT_PNG;
    if( !( IMG_Init( imgFlags ) & imgFlags ) ) {
        throw std::runtime_error(IMG_GetError() );
    }
}

GoSDL::Window::~Window() {

	SDL_DestroyRenderer( mRenderer );
	SDL_DestroyWindow( mWindow );
	mWindow = NULL;
	mRenderer = NULL;

	// Quit SDL subsystems
	Mix_Quit();
    IMG_Quit();
	SDL_Quit();

}

void GoSDL::Window::show() {
    SDL_ShowWindow(mWindow);

    Uint32 newTicks;
    SDL_Event e;

    mShouldRun = true;

    // Main game loop
    while (mShouldRun) {

        // Get ticks
        newTicks = SDL_GetTicks();

        // Get ticks from last frame and compare with framerate
        if (newTicks - mLastTicks < mUpdateInterval) {
            continue;
        }

        // Event loop
        while (SDL_PollEvent (&e)) {

            switch (e.type) {

            case SDL_QUIT:
                // Yes, goto: http://stackoverflow.com/a/1257776/276451
                goto exit;
                break;

            case SDL_KEYDOWN:
                buttonDown(e.key.keysym.sym);
                break;

            case SDL_KEYUP:
                buttonUp(e.key.keysym.sym);
                break;

            case SDL_MOUSEBUTTONDOWN:
                mouseButtonDown(e.button.button);
                break;

            case SDL_MOUSEBUTTONUP:
                mouseButtonUp(e.button.button);
                break;
            }

        }

        update();
        draw();

        SDL_RenderClear (mRenderer);
        GoSDL::DrawingQueueIterator qIt;
        const GoSDL::DrawingQueueOperation * op;

        for (qIt = mDrawingQueue.begin(); qIt != mDrawingQueue.end(); ++qIt) {
            op = &(qIt->second);
            SDL_SetTextureAlphaMod(op->mTexture, op->mAlpha);
            SDL_SetTextureColorMod(op->mTexture, op->mColor.r, op->mColor.g, op->mColor.b);

            int res = SDL_RenderCopyEx(this->mRenderer,
                             op->mTexture,
                             NULL,
                             &(op->mDstRect),
                             op->mAngle,
                             NULL,
                             SDL_FLIP_NONE);

            if (res != 0) {
                printf("ERROR %s \n", SDL_GetError());
            }
        }

        mDrawingQueue.clear();


        SDL_RenderPresent (mRenderer);

        mLastTicks = newTicks;
    }
exit:
    ;
}

void GoSDL::Window::close() {
    mShouldRun = false;
}

void GoSDL::Window::enqueueDraw(SDL_Texture * texture, SDL_Rect destRect, double angle, float z, Uint8 alpha, SDL_Color color) {
    GoSDL::DrawingQueueOperation op;
    op.mTexture = texture;
    op.mDstRect = destRect;
    op.mAngle = angle;
    op.mAlpha = alpha;
    op.mColor = color;

    mDrawingQueue.draw(z, op);
}

int GoSDL::Window::getMouseX (){
    int x;
    SDL_GetMouseState(&x, NULL);

    return x;
}

int GoSDL::Window::getMouseY (){
    int y;
    SDL_GetMouseState(NULL, &y);

    return y;
}


