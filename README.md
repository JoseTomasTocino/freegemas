<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_logo.png"><br>
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_gems.png"><br>
</p>

__Freegemas__ is an open source version of the well known Bejeweled, for GNU/Linux, Windows, Mac and Playstation Vita. It's written in C++ using [SDL3](https://www.libsdl.org/). In the past it used Gosu instead of SDL3, and the old repository can be found at [Google Code](https://code.google.com/archive/p/freegemas/).

<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/screenshot_1.png">
</p>    
        


## Installation on Debian-based GNU/Linux systems

SDL3 and its satellite libraries are built from the bundled submodules, so only
the system development headers they need have to be installed:

    sudo apt-get install git build-essential cmake \
        zlib1g-dev libasound2-dev libxkbcommon-dev libdrm-dev libgl1-mesa-dev \
        libgbm-dev libwayland-dev libdecor-0-dev

After that, clone the repo:

    git clone --recursive https://github.com/JoseTomasTocino/freegemas.git
    
Do an out-of-source compilation and run the program:

    cd freegemas
    mkdir build
    cd build
    cmake ..
    cmake --build .
    ./freegemas

## Installation on OS X

This assumes that you are already using [Homebrew](https://brew.sh/). SDL3,
SDL3_mixer, SDL3_ttf and JsonCpp are built from the bundled submodules, so
Homebrew is only needed for CMake:

    brew install cmake

After that, clone the repo:

    git clone --recursive https://github.com/JoseTomasTocino/freegemas.git
    
Do an out-of-source compilation, install the app bundle and run it:

    cd freegemas
    cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PWD/dist"
    cmake --build build
    strip build/freegemas.app/Contents/MacOS/freegemas
    cmake --install build
    open dist/freegemas.app

## Installation on Playstation Vita

For building for Vita, the [Vita SDK](https://vitasdk.org) should be installed.

After that, clone the repo:

    git clone --recursive https://github.com/JoseTomasTocino/freegemas.git

Do an out-of-source compilation:

    cd freegemas
    mkdir vita
    cd vita
    cmake -DCMAKE_TOOLCHAIN_FILE="${VITASDK}/share/vita.toolchain.cmake" ..
    cmake --build .

Now ``freegemas.vpk`` can be tranfered and installed on Vita.

## Music licensing

The music in the game is [Easy Lemon by Kevin MacLeod](https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1200076)
Licensed under [Creative Commons: By Attribution 3.0](https://creativecommons.org/licenses/by/3.0/)
