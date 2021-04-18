#include "GameSounds.h"

void GameSounds::loadResources()
{
    options.loadResources();

    if (options.getSoundEnabled()) {
        mSfxMatch1.setSample("media/match1.ogg");
        mSfxMatch2.setSample("media/match2.ogg");
        mSfxMatch3.setSample("media/match3.ogg");
        mSfxSelect.setSample("media/select.ogg");
        mSfxFall.setSample("media/fall.ogg");
    }

}

void GameSounds::playSoundSelect()
{
        mSfxSelect.play(0.3);
}

void GameSounds::playSoundFall()
{
    mSfxFall.play(0.3);
}

void GameSounds::playSoundMatch1()
{
    mSfxMatch1.play(0.25);
}

void GameSounds::playSoundMatch2()
{
    mSfxMatch2.play(0.25);
}

void GameSounds::playSoundMatch3()
{
    mSfxMatch3.play(0.25);
}
