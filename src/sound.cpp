#include "sound.h"
#include <cstdio>

GoSDL::Sound::~Sound ()
{
    Mix_FreeChunk(mSample);
}

void GoSDL::Sound::setSample (std::string path)
{
    mSample = Mix_LoadWAV(path.c_str());

    if(!mSample)
    {
        printf("Mix_LoadWAV: %s\n", Mix_GetError());
    }
}

void GoSDL::Sound::play (float vol)
{
    Mix_VolumeChunk(mSample, 128 * vol);
    Mix_PlayChannel(-1, mSample, 0);
}