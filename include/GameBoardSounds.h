#ifndef GAME_BOARD_SOUNDS_H
#define GAME_BOARD_SOUNDS_H

#include "go_sound.h"


class GameBoardSounds
{

public:
    /// Loads the sounds
    void loadResources();

    void playSoundSelect();
    void playSoundFall();
    void playSoundMatch1();
    void playSoundMatch2();
    void playSoundMatch3();

private:

    /// @{
    /// @name Sounds of the game
    GoSDL::Sound mSfxMatch1, mSfxMatch2, mSfxMatch3;
    GoSDL::Sound mSfxSelect;
    GoSDL::Sound mSfxFall;
    /// @}
};

#endif