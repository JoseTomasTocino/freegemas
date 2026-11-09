#include "go_window.h"
#include "Util.h"
#include "log.h"

#include <iostream>
#include <stdexcept>

using namespace std;


GoSDL::Window::Window (unsigned width, unsigned height, std::string caption, Uint32 updateInterval) :
    mUpdateInterval(updateInterval)
{
    // Init SDL
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO | SDL_INIT_GAMEPAD))
    {
        throw std::runtime_error(SDL_GetError());
    }

    if( !MIX_Init())
    {
        throw std::runtime_error(SDL_GetError());
    }

    mMixer = MIX_CreateMixerDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, NULL);
    if (!this->mMixer) {
        throw std::runtime_error(SDL_GetError());
    }

    // Create window
    SDL_PropertiesID properties = SDL_CreateProperties();
    SDL_SetStringProperty(properties, SDL_PROP_WINDOW_CREATE_TITLE_STRING, caption.c_str());
    SDL_SetNumberProperty(properties, SDL_PROP_WINDOW_CREATE_WIDTH_NUMBER, width);
    SDL_SetNumberProperty(properties, SDL_PROP_WINDOW_CREATE_HEIGHT_NUMBER, height);
    SDL_SetNumberProperty(properties, SDL_PROP_WINDOW_CREATE_FLAGS_NUMBER, SDL_WINDOW_RESIZABLE | SDL_WINDOW_HIGH_PIXEL_DENSITY);
    mWindow =  SDL_CreateWindowWithProperties(properties);
    SDL_DestroyProperties(properties);

    // If window could not be created, throw an error
    if (mWindow == NULL )
    {
        throw std::runtime_error(SDL_GetError());
    }

    // Create renderer for the window
    mRenderer = SDL_CreateRenderer( mWindow,0 );

    // If rendered could not be created, throw an error
    if (mRenderer == NULL )
    {
        throw std::runtime_error(SDL_GetError());
    }

    // For proper scaling in all resolutions
    // SDL_SetRenderLogicalPresentation(mRenderer, width, height);

    // Initialize renderer color
    SDL_SetRenderDrawColor( mRenderer, 0, 0, 0, 255 );

    // Set full screen mode
    mOptions.loadResources();
    setFullscreen(mOptions.getFullscreenEnabled());

    // Hide cursor
    SDL_ShowCursor();
}

GoSDL::Window::~Window()
{
    closeAllGameControllers();

	SDL_DestroyRenderer( mRenderer );
	SDL_DestroyWindow( mWindow );
    mRenderer = NULL;
	mWindow = NULL;

	// Quit SDL subsystems
	MIX_Quit();
	SDL_Quit();
}

void GoSDL::Window::show()
{
    // To poll events
    SDL_Event e;

    // Show the window
    SDL_ShowWindow(mWindow);

    mShouldRun = true;
    mApplicationActive = true;

    // Main game loop
    while (mShouldRun) {

        // Event loop
        while (SDL_PollEvent (&e))
        {
            switch (e.type)
            {
            case SDL_EVENT_WILL_ENTER_BACKGROUND:
                mApplicationActive = false;
                break;

            case SDL_EVENT_WILL_ENTER_FOREGROUND:
                mApplicationActive = true;
                break;

            case SDL_EVENT_QUIT:
                // Yes, goto: http://stackoverflow.com/a/1257776/276451
                goto exit;
                break;

            case SDL_EVENT_KEY_DOWN:
                mMouseActive = false;
                buttonDown(e.key.key);
                break;

            case SDL_EVENT_KEY_UP:
                buttonUp(e.key.key);
                break;

            case SDL_EVENT_MOUSE_MOTION:
                mMouseActive = true;
                mMouseX = e.motion.x;
                mMouseY = e.motion.y;
                break;

            case SDL_EVENT_MOUSE_BUTTON_DOWN:
                mMouseActive = true;
                mouseButtonDown(e.button.button);
                break;

            case SDL_EVENT_MOUSE_BUTTON_UP:
                mouseButtonUp(e.button.button);
                break;

            case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
                mMouseActive = false;
                controllerButtonDown(e.gbutton.button);
                break;

            case SDL_EVENT_GAMEPAD_ADDED:
                openGameController(e.gbutton.which);
                break;

            case SDL_EVENT_GAMEPAD_REMOVED:
                closeDisconnectedGameControllers();
                break;
            }
        }

        if (mApplicationActive)
        {
            Uint32 gameCycleTicks = SDL_GetTicks();

            gameLoop();

            // Limit to framerate
            gameCycleTicks = SDL_GetTicks() - gameCycleTicks;
            if (gameCycleTicks < mUpdateInterval)
            {
                SDL_Delay(mUpdateInterval - gameCycleTicks);
            }
        }
        else
        {
            SDL_WaitEvent(nullptr);
        }
    }
    // Exit point for goto within switch
exit:
    ;
}

void GoSDL::Window::gameLoop()
{
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
        int res = SDL_RenderTextureRotated(this->mRenderer,
                        op->mTexture,
                        NULL,
                        &(op->mDstRect),
                        op->mAngle,
                        NULL,
                        SDL_FLIP_NONE);

        // Check for errors when drawing
        if (!res)
        {
            printf("ERROR %s \n", SDL_GetError());
        }
    }

    // Empty the drawing queue
    mDrawingQueue.clear();

    // Update the screen
    SDL_RenderPresent (mRenderer);
}

void GoSDL::Window::close()
{
    mShouldRun = false;
}

void GoSDL::Window::enqueueDraw(SDL_Texture * texture, SDL_FRect destRect, double angle, float z, Uint8 alpha, SDL_Color color)
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
     if (SDL_IsGamepad(index)) {
        SDL_Gamepad * controller = SDL_OpenGamepad(index);
        lDEBUG << "Adding controller: " << SDL_GetGamepadName(controller);
        gameControllers.push_back(controller);
    }
}

void GoSDL::Window::closeDisconnectedGameControllers() {
    std::vector<SDL_Gamepad*> currentControllers;
    for (int i = 0; i < int(gameControllers.size()); i++) {
        if (!SDL_GamepadConnected(gameControllers[i])) {
            lDEBUG << "Removing controller: " << SDL_GetGamepadName(gameControllers[i]);
            SDL_CloseGamepad(gameControllers[i]);
            gameControllers[i] = NULL;
        } else {
            currentControllers.push_back(gameControllers[i]);
        }
    }

    gameControllers = currentControllers;
}

void GoSDL::Window::closeAllGameControllers() {
    for (int i = 0; i < int(gameControllers.size()); i++) {
        lDEBUG << "Removing controller: " << SDL_GetGamepadName(gameControllers[i]);
        SDL_CloseGamepad(gameControllers[i]);
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
