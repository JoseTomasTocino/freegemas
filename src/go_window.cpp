#include "go_window.h"
#include "Util.h"
#include "log.h"

#include <iostream>
#include <stdexcept>

using namespace std;


GoSDL::Window::Window (unsigned width, unsigned height, std::string caption, Uint32 updateInterval) :
    mUpdateInterval(updateInterval)
{
    // Get starting ticks
    mLastTicks = SDL_GetTicks();

    // Init SDL
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMECONTROLLER) < 0)
    {
        throw std::runtime_error(SDL_GetError());
    }

    // Set texture filtering to linear
    if (!SDL_SetHint( SDL_HINT_RENDER_SCALE_QUALITY, "1" ) )
    {
        cerr << "Warning: Linear texture filtering not enabled!" << endl;
    }

    if( Mix_OpenAudio( MIX_DEFAULT_FREQUENCY, MIX_DEFAULT_FORMAT, MIX_DEFAULT_CHANNELS, 4096 ) < 0 )
    {
        throw std::runtime_error(Mix_GetError());
    }

    // Create window
    mWindow = SDL_CreateWindow( caption.c_str(),
                                SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                                #ifdef __vita__
                                    960, 544,
                                #else
                                    width, height,
                                #endif
                                SDL_WINDOW_RESIZABLE );

    // If window could not be created, throw an error
    if (mWindow == NULL )
    {
        throw std::runtime_error(SDL_GetError());
    }

    // Create renderer for the window
    mRenderer = SDL_CreateRenderer( mWindow, -1, SDL_RENDERER_ACCELERATED );

    // If rendered could not be created, throw an error
    if (mRenderer == NULL )
    {
        throw std::runtime_error(SDL_GetError());
    }

    // For proper scaling in all resolutions
    SDL_RenderSetLogicalSize(mRenderer, width, height);

    // Initialize renderer color
    SDL_SetRenderDrawColor( mRenderer, 0, 0, 0, 255 );

    // Initialize PNG loading
    int imgFlags = IMG_INIT_PNG;

    if( !( IMG_Init( imgFlags ) & imgFlags ) )
    {
        throw std::runtime_error(IMG_GetError() );
    }

    // Set full screen mode
    mOptions.loadResources();
    setFullscreen(mOptions.getFullscreenEnabled());

    // Hide cursor
    SDL_ShowCursor(0);
}

GoSDL::Window::~Window()
{
    closeAllGameControllers();

	SDL_DestroyRenderer( mRenderer );
	SDL_DestroyWindow( mWindow );
    mRenderer = NULL;
	mWindow = NULL;

	// Quit SDL subsystems
	Mix_Quit();
    IMG_Quit();
	SDL_Quit();
}

void GoSDL::Window::show()
{
    // To store the ticks passed between frames
    Uint32 newTicks;

    // To poll events
    SDL_Event e;

    // Show the window
    SDL_ShowWindow(mWindow);

    mShouldRun = true;

    // Main game loop
    while (mShouldRun) {

        // Get ticks
        newTicks = SDL_GetTicks();

        // Get ticks from last frame and compare with framerate
        if (newTicks - mLastTicks < mUpdateInterval)
        {
            SDL_Delay(mUpdateInterval - (newTicks - mLastTicks));
            continue;
        }

        // Event loop
        while (SDL_PollEvent (&e))
        {
            switch (e.type)
            {

            case SDL_QUIT:
                // Yes, goto: http://stackoverflow.com/a/1257776/276451
                goto exit;
                break;

            case SDL_KEYDOWN:
                mMouseActive = false;
                buttonDown(e.key.keysym.sym);
                break;

            case SDL_KEYUP:
                buttonUp(e.key.keysym.sym);
                break;

            case SDL_MOUSEMOTION:
                mMouseActive = true;
                mMouseX = e.motion.x;
                mMouseY = e.motion.y;
                break;

            case SDL_MOUSEBUTTONDOWN:
                mMouseActive = true;
                mouseButtonDown(e.button.button);
                break;

            case SDL_MOUSEBUTTONUP:
                mouseButtonUp(e.button.button);
                break;

            case SDL_CONTROLLERBUTTONDOWN:
                mMouseActive = false;
                controllerButtonDown(e.cbutton.button);
                break;

            case SDL_CONTROLLERDEVICEADDED:
                openGameController(e.cdevice.which);
                break;

            case SDL_CONTROLLERDEVICEREMOVED:
                closeDisconnectedGameControllers();
                break;
            }
        }

        // Process logic
        update();

        // Process drawing
        draw();

        // Render the background clear
        SDL_RenderClear (mRenderer);

        // Iterator for drawing operations
        GoSDL::DrawingQueueIterator qIt;
        const GoSDL::DrawingQueueOperation * op;

        // Iterate all pending drawing operations
        for (qIt = mDrawingQueue.begin(); qIt != mDrawingQueue.end(); ++qIt)
        {
            // Get a reference of the current operation
            op = &(qIt->second);

            // Set transparency
            SDL_SetTextureAlphaMod(op->mTexture, op->mAlpha);

            // Set coloring
            SDL_SetTextureColorMod(op->mTexture, op->mColor.r, op->mColor.g, op->mColor.b);

            // Draw the texture
            int res = SDL_RenderCopyEx(this->mRenderer,
                             op->mTexture,
                             NULL,
                             &(op->mDstRect),
                             op->mAngle,
                             NULL,
                             SDL_FLIP_NONE);

            // Check for errors when drawing
            if (res != 0)
            {
                printf("ERROR %s \n", SDL_GetError());
            }
        }

        // Empty the drawing queue
        mDrawingQueue.clear();

        // Update the screen
        SDL_RenderPresent (mRenderer);

        // Update the ticks
        mLastTicks = newTicks;
    }

    // Exit point for goto within switch
exit:
    ;
}

void GoSDL::Window::close()
{
    mShouldRun = false;
}

void GoSDL::Window::enqueueDraw(SDL_Texture * texture, SDL_Rect destRect, double angle, float z, Uint8 alpha, SDL_Color color)
{
    // Create the new drawing operation
    GoSDL::DrawingQueueOperation op;

    // Fill the operation
    op.mTexture = texture;
    op.mDstRect = destRect;
    op.mAngle = angle;
    op.mAlpha = alpha;
    op.mColor = color;

    // Store it in the container, sorted by depth
    mDrawingQueue.draw(z, op);
}

void GoSDL::Window::openGameController(Sint32 index) {
     if (SDL_IsGameController(index)) {
        SDL_GameController * controller = SDL_GameControllerOpen(index);
        lDEBUG << "Adding controller: " << SDL_GameControllerName(controller);
        gameControllers.push_back(controller);
    }
}

void GoSDL::Window::closeDisconnectedGameControllers() {
    std::vector<SDL_GameController*> currentControllers;
    for (int i = 0; i < int(gameControllers.size()); i++) {
        if (!SDL_GameControllerGetAttached(gameControllers[i])) {
            lDEBUG << "Removing controller: " << SDL_GameControllerName(gameControllers[i]);
            SDL_GameControllerClose(gameControllers[i]);
            gameControllers[i] = NULL;
        } else {
            currentControllers.push_back(gameControllers[i]);
        }
    }

    gameControllers = currentControllers;
}

void GoSDL::Window::closeAllGameControllers() {
    for (int i = 0; i < int(gameControllers.size()); i++) {
        lDEBUG << "Removing controller: " << SDL_GameControllerName(gameControllers[i]);
        SDL_GameControllerClose(gameControllers[i]);
        gameControllers[i] = NULL;
    }
}

void GoSDL::Window::setFullscreen(bool value)
{
    if (value) {
        SDL_SetWindowFullscreen(mWindow, SDL_WINDOW_FULLSCREEN);
    } else {
        SDL_SetWindowFullscreen(mWindow, 0);
    }
}
