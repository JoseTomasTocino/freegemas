#include "go_music.h"
#include "Util.h"
#include <cstdio>

GoSDL::Music::~Music ()
{
    if (mSample_track)
        MIX_StopTrack(this->mSample_track, 0);
    if (mSample)
        MIX_DestroyAudio(mSample);
    if (mSample_track)
        MIX_DestroyTrack(mSample_track);
}

void GoSDL::Music::setWindow(Window *parentWindow)
{
    mParentWindow = parentWindow;
}

void GoSDL::Music::setSample(std::string path)
{
    std::string mPath = getBasePath() + path;
    mSample = MIX_LoadAudio(mParentWindow->getMixer(), mPath.c_str(), false);

    if (!mSample)
    {
        SDL_Log("MIX_LoadAudio ERROR: %s\n", SDL_GetError());
        return;
    }
    if (!mSample_track)
    {
        mSample_track = MIX_CreateTrack(mParentWindow->getMixer());
    }    if (!mSample_track)
    {
        SDL_Log("MIX_CreateTrack ERROR: %s\n", SDL_GetError());
        return;
    }
    MIX_SetTrackAudio(mSample_track, mSample);
}

void GoSDL::Music::play (float vol)
{
    if (!mSample || !mSample_track)
        return;

    MIX_StopTrack(mSample_track, 0);
    MIX_SetTrackGain(mSample_track, vol);
    
    SDL_PropertiesID properties = SDL_CreateProperties();
    SDL_SetNumberProperty(properties, MIX_PROP_PLAY_LOOPS_NUMBER, -1);
    SDL_SetNumberProperty(properties, MIX_PROP_PLAY_FADE_IN_MILLISECONDS_NUMBER, 200);
    MIX_PlayTrack(mSample_track, properties);
    SDL_DestroyProperties(properties);
}

void GoSDL::Music::stop()
{
    if (!mSample_track)
        return;

    size_t frames = MIX_TrackMSToFrames(mSample_track, 200);
    MIX_StopTrack(mSample_track, frames);
}

bool GoSDL::Music::isPlaying()
{
    if (!mSample_track)
        return false;
    return MIX_TrackPlaying(mSample_track);
}
