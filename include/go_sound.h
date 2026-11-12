#ifndef SOUND_H
#define SOUND_H

#include <string>

#include "go_window.h"

#include <SDL3_mixer/SDL_mixer.h>

namespace GoSDL {
    class Sound {

    public:
        ~Sound();

        void setWindow(Window * parentWindow);
        void setSample(std::string path);
        void unload();
        void play(float vol = 1);

    private:
        // Parent window
        Window * mParentWindow = NULL;

        MIX_Audio * mSample = nullptr;
        MIX_Track * mSample_track = nullptr;
    };

}

#endif
