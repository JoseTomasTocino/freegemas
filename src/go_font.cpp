#include <SDL.h>

#include <memory>
#include <cstdio>
#include <stdexcept>

#include "go_font.h"
#include "Util.h"

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
    mPath = getBasePath() + path;
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

GoSDL::Image GoSDL::Font::renderTextWithShadow (std::string text, SDL_Color color, int shadowX, int shadowY, SDL_Color shadowColor) {

    SDL_Surface * textSurface = TTF_RenderUTF8_Blended(mFont, text.c_str(), color);
    SDL_Surface * shadowSurface = TTF_RenderUTF8_Blended(mFont, text.c_str(), shadowColor);
    return surfaceToImageWithShadow(textSurface, shadowSurface, shadowX, shadowY);
}

GoSDL::Image GoSDL::Font::renderBlock (std::string text, SDL_Color color, unsigned width) {

    SDL_Surface * tempSurface = TTF_RenderUTF8_Blended_Wrapped(mFont, text.c_str(), color, width);
    return surfaceToImage(tempSurface);
}

GoSDL::Image GoSDL::Font::renderBlockWithShadow (std::string text, SDL_Color color, unsigned width, int shadowX, int shadowY, SDL_Color shadowColor) {

    SDL_Surface * textSurface = TTF_RenderUTF8_Blended_Wrapped(mFont, text.c_str(), color, width);
    SDL_Surface * shadowSurface = TTF_RenderUTF8_Blended_Wrapped(mFont, text.c_str(), shadowColor, width);
    return surfaceToImageWithShadow(textSurface, shadowSurface, shadowX, shadowY);
}

GoSDL::Image GoSDL::Font::surfaceToImage (SDL_Surface * tempSurface) {
    SDL_Texture * tempTexture = SDL_CreateTextureFromSurface(mParentWindow->getRenderer(), tempSurface);

    SDL_FreeSurface(tempSurface);

    GoSDL::Image img;
    img.setWindow(mParentWindow);
    img.setTexture(tempTexture);

    return img;
}

GoSDL::Image GoSDL::Font::surfaceToImageWithShadow (SDL_Surface * textSurface, SDL_Surface * shadowSurface, int shadowX, int shadowY) {
    SDL_Rect rect;

    SDL_Surface * tempSurface = SDL_CreateRGBSurfaceWithFormat(0, shadowX + shadowSurface->w, shadowY + shadowSurface->h, 32, SDL_PIXELFORMAT_RGBA32);

    rect.x = shadowX;
    rect.y = shadowY;
    rect.w = shadowSurface->w;
    rect.w = shadowSurface->h;
    SDL_SetSurfaceBlendMode(shadowSurface, SDL_BLENDMODE_NONE);
    SDL_BlitSurface(shadowSurface, NULL, tempSurface, &rect);
    SDL_FreeSurface(shadowSurface);

    rect.x = 0;
    rect.y = 0;
    rect.w = textSurface->w;
    rect.w = textSurface->h;
    SDL_SetSurfaceBlendMode(textSurface, SDL_BLENDMODE_BLEND);
    SDL_BlitSurface(textSurface, NULL, tempSurface, &rect);
    SDL_FreeSurface(textSurface);

    return surfaceToImage(tempSurface);
}
