#include "go_sound.h"
#include "Util.h"
#include <cstdio>

GoSDL::Sound::~Sound ()
{
    unload();
}

void GoSDL::Sound::setWindow(Window *parentWindow)
{
    mParentWindow = parentWindow;
}

void GoSDL::Sound::setSample(std::string path)
{
    std::string mPath = getBasePath() + path;
    mSample = MIX_LoadAudio(mParentWindow->getMixer(), mPath.c_str(), true);

    if(!mSample)
    {
        printf("MIX_LoadAudio: %s\n", SDL_GetError());
    }
    if (!mSample_track)
    {
        mSample_track = MIX_CreateTrack(mParentWindow->getMixer());
    }
    if(!mSample_track)
    {
        printf("MIX_CreateTrack: %s\n", SDL_GetError());
    }
}

void GoSDL::Sound::unload ()
{
    if (mSample_track)
        MIX_StopTrack(this->mSample_track, 0);
    if (mSample)
        MIX_DestroyAudio(mSample);
    if (mSample_track)
        MIX_DestroyTrack(mSample_track);
}

void GoSDL::Sound::play (float vol)
{
    if (mSample == nullptr)
    {
        return;
    }
    MIX_SetTrackGain(mSample_track, 128 * vol);
    
    SDL_PropertiesID properties = SDL_CreateProperties();
    SDL_SetNumberProperty(properties, MIX_PROP_PLAY_LOOPS_NUMBER, -1);
    MIX_PlayTrack(mSample_track, properties);
    SDL_DestroyProperties(properties);
}