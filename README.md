Freegemas
=========

<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_logo.png"><br>
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/header_gems.png"><br>
</p>

__Freegemas__ is an open source version of the well known Bejeweled, for GNU/Linux and Windows. It's written in C++ using [SDL2](https://www.libsdl.org/). In the past it used Gosu instead of SDL2, and the old repository can be found at [Google Code](http://freegemas.googlecode.com)

<p align="center">
    <img src="https://raw.githubusercontent.com/JoseTomasTocino/freegemas/static/images/screenshot_1.png">
</p>    
        


## Installing

These instructions are for debian-based GNU/Linux systems. First, you need to install git and gcc:

    sudo apt-get install git build-essential

Next, install SDL2 from the repositories:

    sudo apt-get install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev libsdl2-mixer-dev
    
After that, clone the repo:

    git clone https://github.com/JoseTomasTocino/freegemas.git
    
Finally, cd into the directory, compile and run

    cd freegemas
    make -j4
    ./freegemas.out
    
    
