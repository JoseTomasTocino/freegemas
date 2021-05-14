<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_logo.png"><br>
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_gems.png"><br>
</p>

__Freegemas__ is an open source version of the well known Bejeweled, for GNU/Linux, Windows, Mac and the Playstation Vita. It's written in C++ using [SDL2](https://www.libsdl.org/). In the past it used Gosu instead of SDL2, and the old repository can be found at [Google Code](https://freegemas.googlecode.com)

<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/screenshot_1.png">
</p>    
        


## Installation on Debian-based GNU/Linux systems

First, you need to install git and gcc:

    sudo apt-get install git build-essential cmake

Next, install SDL2 from the repositories:

    sudo apt-get install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev libjsoncpp-dev
    
After that, clone the repo:

    git clone https://github.com/JoseTomasTocino/freegemas.git
    
Do an out-of-source compilation and run the program:

    cd freegemas
    mkdir build
    cd build
    cmake ..
    make
    ./freegemas

## Installation on OS X

This assumes that you are already using [Homebrew](https://brew.sh/). You will need CMake and a few libraries to compile Freegemas:

    brew install cmake sdl2 sdl2_mixer sdl2_ttf sdl2_image gettext jsoncpp

Now follow the instructions above, starting with `git clone`.

## Installation on Playstation Vita

For building for the Vita, the [Vita SDK](https://vitasdk.org) should be installed.

After that, clone the repo:

    git clone https://github.com/JoseTomasTocino/freegemas.git

Do an out-of-source compilation:

    mkdir vita
    cd vita
    cmake -DCMAKE_TOOLCHAIN_FILE="${VITASDK}/share/vita.toolchain.cmake" ..
    make

Now ``freegemas.vpk`` can be tranfered and installed on a Vita.

## Music licensing

The music in the game is [Easy Lemon by Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200076)
Licensed under [Creative Commons: By Attribution 3.0](https://creativecommons.org/licenses/by/3.0/)
