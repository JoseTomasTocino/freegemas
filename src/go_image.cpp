#include "go_image.h"
#include "go_window.h"

#include "log.h"
#include "Util.h"

GoSDL::Image::Image() : mParentWindow(NULL), mWidth(0), mHeight(0)
{ }

GoSDL::Image::Image(GoSDL::Window * parentWindow, string path) :
    mParentWindow(parentWindow), mPath(getBasePath() + path)
{
    loadTexture();
}

GoSDL::Image::Image (const Image & other)
{
    mParentWindow = other.mParentWindow;
    mPath = other.mPath;
    mWidth = other.mWidth;
    mHeight = other.mHeight;
    mTexture = other.mTexture;
}

GoSDL::Image::Image (Image && other)
{
    mParentWindow = other.mParentWindow;
    mPath = other.mPath;
    mWidth = other.mWidth;
    mHeight = other.mHeight;
    mTexture = other.mTexture;

    other.mTexture.reset();
}

GoSDL::Image::~Image()
{
    // Surface destruction happens in the custom deleter of the shared pointer
    mParentWindow = NULL;
}

GoSDL::Image & GoSDL::Image::operator= (GoSDL::Image&& other)
{
    if (this != &other)
    {
        mParentWindow = other.mParentWindow;
        mPath = other.mPath;
        mWidth = other.mWidth;
        mHeight = other.mHeight;
        mTexture = other.mTexture;
    }

    return *this;
}

void GoSDL::Image::setWindow(GoSDL::Window * parentWindow)
{
    mParentWindow = parentWindow;
}

void GoSDL::Image::setPath(std::string path)
{
    mPath = getBasePath() + path;
    loadTexture();
}

bool GoSDL::Image::setWindowAndPath(GoSDL::Window * parentWindow, std::string path)
{
    mParentWindow = parentWindow;
    mPath = getBasePath() + path;
    return loadTexture();
}

bool GoSDL::Image::loadTexture()
{
    // Load texture from file
    SDL_Surface * surface = SDL_LoadSurface(mPath.c_str());
    if (surface == nullptr)
    {
        return false;
    }
    SDL_Texture * texture = SDL_CreateTextureFromSurface(mParentWindow->getRenderer(), surface);
    SDL_DestroySurface(surface);

    if (texture == nullptr)
    {
        return false;
    }

    // Fill the managed pinter
    mTexture.reset(texture, GoSDL::Image::SDL_Texture_Deleter());

    // Get texture's width and height
    SDL_GetTextureSize(mTexture.get(), &mWidth, &mHeight);

    // Set texture filtering mode to nearest
    SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST);

    return true;
}

void GoSDL::Image::setTexture (SDL_Texture * texture)
{
    // Assign the texture
    mTexture.reset(texture, GoSDL::Image::SDL_Texture_Deleter());

    // Get texture's width and height
    SDL_GetTextureSize(mTexture.get(), &mWidth, &mHeight);
}

int GoSDL::Image::getWidth()
{
    return mWidth;
}

int GoSDL::Image::getHeight()
{
    return mHeight;
}


bool GoSDL::Image::draw(int x, int y, int z, double factorX, double factorY, float angle, Uint8 alpha, SDL_Color color)
{
    if (mParentWindow == NULL)
    {
        lDEBUG << "Parent window NULL";
        return false;
    }

    if (mTexture == NULL)
    {
        lDEBUG << "Texture NULL";
        return false;
    }

    SDL_FRect destRect;
    destRect.w = mWidth * factorX;
    destRect.h = mHeight * factorY;
    destRect.x = x;
    destRect.y = y;

    mParentWindow->enqueueDraw(mTexture.get(), destRect, angle, z, alpha, color);

    return true;
}

