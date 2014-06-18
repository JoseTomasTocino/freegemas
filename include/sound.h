#ifndef SOUND_H
#define SOUND_H

#include <SDL2/SDL_mixer.h>
#include <string>

namespace GoSDL {
    class Sound {

    public:
        Sound();
        ~Sound();

        void setSample(std::string path);
        void play(float vol = 1);

    private:
        Mix_Chunk * mSample;
    };

}

#endif