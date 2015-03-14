#ifndef _MUSIC_H_
#define _MUSIC_H_

#include <SDL_mixer.h>
#include <string>

namespace GoSDL {
    class Music {

    public:
        ~Music();

        void setSample(std::string path);
        void play(float vol = 1);
        void stop();

        bool isPlaying();

    private:
        Mix_Music * mSample = nullptr;
    };

}

#endif
