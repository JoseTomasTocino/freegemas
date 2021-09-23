#include "Util.h"

#include <cstdlib>
#include <SDL.h>

std::string getBasePath()
{
    std::string basePathStr;

    char *basePath = SDL_GetBasePath();
    if (basePath) {
        basePathStr = basePath;
        SDL_free(basePath);
    }

    return basePathStr;
}

float getRandomFloat(float a, float b)
{
    float random = ((float) rand()) / (float) RAND_MAX;
    float diff = b - a;
    float r = random * diff;

    return a + r;
}

int getRandomInt (int min, int max)
{
    return min + (rand() % (int)(max - min + 1));
}