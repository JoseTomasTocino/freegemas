#include <SDL.h>

#include <memory>
#include <cstdio>
#include <stdexcept>

#include "go_font.h"

GoSDL::Font::Font()
{
    checkInit();
}

GoSDL::Font::~Font()
{
    if (mFont != nullptr)
    {
        TTF_CloseFont(mFont);
        mFont = nullptr;
    }
}

void GoSDL::Font::checkInit ()
{
    if (!TTF_WasInit())
    {
        TTF_Init(); // TODO: check for errors
    }
}

void GoSDL::Font::setPathAndSize(std::string path, unsigned size) {
    mPath = path;
    mSize = size;

    if (mFont != nullptr) {
        TTF_CloseFont(mFont);
        mFont = nullptr;
    }

    mFont = TTF_OpenFont(mPath.c_str(), mSize);

    if (mFont == NULL) {
        printf("Oh My Goodness, an error : %s\n", TTF_GetError());
        throw std::runtime_error("WAT");
    }

    // TODO: check for errors
}

void GoSDL::Font::setAll(Window * parentWindow, std::string path, unsigned size) {
    setWindow(parentWindow);
    setPathAndSize(path, size);
}

int GoSDL::Font::getTextWidth(std::string text) {
    if (!mFont) return 0;

    int w;
    TTF_SizeUTF8(mFont, text.c_str(), &w, NULL);

    return w;
}

void GoSDL::Font::setWindow (Window * parentWindow) {
    mParentWindow = parentWindow;
}

GoSDL::Image GoSDL::Font::renderText (std::string text, SDL_Color color) {

    SDL_Surface * tempSurface = TTF_RenderUTF8_Blended(mFont, text.c_str(), color);
    return surfaceToImage(tempSurface);
}

GoSDL::Image GoSDL::Font::renderBlock (std::string text, SDL_Color color, unsigned width) {

    SDL_Surface * tempSurface = TTF_RenderUTF8_Blended_Wrapped(mFont, text.c_str(), color, width);
    return surfaceToImage(tempSurface);
}

GoSDL::Image GoSDL::Font::surfaceToImage (SDL_Surface * tempSurface) {
    SDL_Texture * tempTexture = SDL_CreateTextureFromSurface(mParentWindow->getRenderer(), tempSurface);

    SDL_FreeSurface(tempSurface);

    GoSDL::Image img;
    img.setWindow(mParentWindow);
    img.setTexture(tempTexture);

    return img;
}
