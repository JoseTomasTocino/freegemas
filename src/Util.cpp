#include "Util.h"

#include <cstdlib>

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