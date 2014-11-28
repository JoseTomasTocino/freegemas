#ifndef _CUSTOMFONT_H_
#define _CUSTOMFONT_H_

#include <string>

#include "go_window.h"
#include "go_image.h"

#include <SDL_ttf.h>


namespace GoSDL {

    class Font {

    public:
        Font();

        void setWindow(Window * parentWindow);
        void setPathAndSize(std::string path, unsigned size);
        void setAll(Window * parentWindow, std::string path, unsigned size);

        int getTextWidth(std::string text);

        GoSDL::Image renderText(std::string text, SDL_Color color = {255, 255, 255, 255});
        GoSDL::Image renderBlock(std::string text, SDL_Color color, unsigned width);

        ~Font();

    private:

        // TTF_Init wrapper
        void checkInit();

        // Receives a surface and returns a pointer to an image (containing a texture)
        GoSDL::Image surfaceToImage (SDL_Surface * tempSurface);

        // Parent window
        Window * mParentWindow = NULL;

        // Path to the font file
        std::string mPath;

        // Size of the font
        unsigned mSize;

        // Actual font
        TTF_Font * mFont = NULL;
    };
}


#endif /* _CUSTOMFONT_H_ */
