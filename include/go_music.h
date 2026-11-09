#ifndef _MUSIC_H_
#define _MUSIC_H_

#include <string>

#include "go_window.h"

#include <SDL3_mixer/SDL_mixer.h>

namespace GoSDL {
    class Music {

    public:
        ~Music();

        void setWindow(Window * parentWindow);
        void setSample(std::string path);
        void play(float vol = 1);
        void stop();

        bool isPlaying();

    private:
        // Parent window
        Window * mParentWindow = NULL;

        MIX_Audio * mSample = nullptr;
        MIX_Track * mSample_track = nullptr;
    };

}

#endif
