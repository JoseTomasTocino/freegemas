#include "image.h"
#include "window.h"

#include "log.h"

GoSDL::Image::Image() : mParentWindow(NULL), mWidth(0), mHeight(0) { }

GoSDL::Image::Image(GoSDL::Window * parentWindow, string path) :
    mParentWindow(parentWindow), mPath(path) {

    loadTexture();
}

GoSDL::Image::~Image(){
    /*
    if (mTexture) {
        SDL_DestroyTexture(mTexture);
    } //*/

    mParentWindow = NULL;
}

void GoSDL::Image::setWindow(GoSDL::Window * parentWindow) {
    mParentWindow = parentWindow;
}

void GoSDL::Image::setPath(std::string path) {
    mPath = path;
    loadTexture();
}

void GoSDL::Image::setWindowAndPath(GoSDL::Window * parentWindow, std::string path) {
    mParentWindow = parentWindow;
    mPath = path;
    loadTexture();
}

void GoSDL::Image::loadTexture() {

    // Load texture from file
    mTexture.reset(IMG_LoadTexture(mParentWindow->getRenderer(), mPath.c_str()), GoSDL::Image::SDL_Texture_Deleter());

    // Get texture's width and height
    SDL_QueryTexture(mTexture.get(), NULL, NULL, &mWidth, &mHeight);
}

void GoSDL::Image::setTexture (SDL_Texture * texture) {

    // Assign the texture
    mTexture.reset(texture, GoSDL::Image::SDL_Texture_Deleter());

    // Get texture's width and height
    SDL_QueryTexture(mTexture.get(), NULL, NULL, &mWidth, &mHeight);
}

int GoSDL::Image::getWidth() {
    return mWidth;
}

int GoSDL::Image::getHeight() {
    return mHeight;
}


void GoSDL::Image::draw(int x, int y, int z, double factorX, double factorY, float angle, Uint8 alpha, SDL_Color color) {
    if (mParentWindow == NULL || mTexture == NULL) return;

    SDL_Rect destRect;
    destRect.w = mWidth * factorX;
    destRect.h = mHeight * factorY;
    destRect.x = x;
    destRect.y = y;

    mParentWindow->enqueueDraw(mTexture.get(), destRect, angle, z, alpha, color);
}

