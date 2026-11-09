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
        SDL_Log("MIX_LoadAudio: %s\n", SDL_GetError());
        return;
    }
    if (!mSample_track)
    {
        mSample_track = MIX_CreateTrack(mParentWindow->getMixer());
    }
    if(!mSample_track)
    {
        SDL_Log("MIX_CreateTrack: %s\n", SDL_GetError());
        return;
    }
    MIX_SetTrackAudio(mSample_track, mSample);
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
    if (mSample_track == nullptr)
    {
        return;
    }
    MIX_SetTrackGain(mSample_track, vol);
    MIX_PlayTrack(mSample_track, 0);
}