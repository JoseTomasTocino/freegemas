#include "GameBoardSounds.h"

void GameBoardSounds::loadResources()
{
    mSfxMatch1.setSample("media/match1.ogg");
    mSfxMatch2.setSample("media/match2.ogg");
    mSfxMatch3.setSample("media/match3.ogg");
    mSfxSelect.setSample("media/select.ogg");
    mSfxFall.setSample("media/fall.ogg");
}

void GameBoardSounds::playSoundSelect()
{
    mSfxSelect.play(0.3);
}

void GameBoardSounds::playSoundFall()
{
    mSfxFall.play(0.3);
}

void GameBoardSounds::playSoundMatch1()
{
    mSfxMatch1.play(0.25);
}

void GameBoardSounds::playSoundMatch2()
{
    mSfxMatch2.play(0.25);
}

void GameBoardSounds::playSoundMatch3()
{
    mSfxMatch3.play(0.25);
}
