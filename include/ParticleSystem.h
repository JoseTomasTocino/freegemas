#ifndef _PARTICULAS_H_
#define _PARTICULAS_H_

#include "go_image.h"

#include "Animation.h"
#include "log.h"
#include "Util.h"

#include <ctime>
#include <vector>
#include <cmath>

#define lim 0.70

namespace GoSDL {
    class Window;
}

struct Particle{

    Particle(float angle, float distance, float size, int totalSteps, GoSDL::Image *img, SDL_Color color) :
        mAngle(angle), mDistance(distance), mSize(size), mTotalSteps(totalSteps), mImage(img), mColor(color), mCurrentStep(0), mPosX(0), mPosY(0), mStartTime(0)
    { }

    void update() {
        if (mStartTime == 0) {
            mStartTime = SDL_GetTicks();
        }

        mCurrentStep = SDL_GetTicks() - mStartTime;
        if (mCurrentStep > mTotalSteps) {
            mCurrentStep = mTotalSteps;
        }

        float tempPos = Animacion::easeOutQuart(mCurrentStep, 0, 1, mTotalSteps);

        if (tempPos >= lim) {
            mAlpha = 255 * (1 - (tempPos - lim) / (1 - lim));
        } else {
            mAlpha = 255;
        }

        mSizeCoef = mSize * (1 - tempPos);

        mPosX = tempPos * mDistance * std::cos(mAngle * 3.141592 / 180) - mImage->getWidth() * mSizeCoef / 2;
        mPosY = tempPos * mDistance * std::sin(mAngle * 3.141592 / 180) - mImage->getHeight() * mSizeCoef / 2;


    }

    void draw(int oX, int oY){
        mImage->draw(oX + mPosX, oY + mPosY, 7, mSizeCoef, mSizeCoef, 0, 255, mColor);
    }

    float estado(){
        return (float)mCurrentStep / (float)mTotalSteps;
    }


    float mAngle;

    float mDistance;

    float mSize;

    int mTotalSteps;

    GoSDL::Image *mImage;

    SDL_Color mColor;

    Uint8 mAlpha;

    int mCurrentStep;

    float mPosX;

    float mPosY;

    float mSizeCoef;

    unsigned int mStartTime;
};


class ParticleSystem{

public:
    ParticleSystem(GoSDL::Image *imgParticle1,
                      GoSDL::Image *imgParticle2,
                      unsigned particleQuantity,
                      unsigned totalSteps,
                      int x,
                      int y,
                      unsigned distance=200,
                      float scale=1,
                      SDL_Color color = {255, 255, 255, 255}) :

        mParticleQuantity(particleQuantity),
        mStartTime(0),
        mTotalSteps(totalSteps),
        mCurrentStep(0),
        mDistance(distance),
        mScale(scale),
        mColor(color),
        mPosX(x),
        mPosY(y),
        mActive(true)
    {
        // Reserve the space for the particles
        mParticleVector.reserve(mParticleQuantity);

        // Create the particles
        for (size_t i = 0; i < mParticleQuantity; ++i)
        {
            mParticleVector.push_back(Particle(getRandomInt(0, 360),
                                    getRandomFloat(0, 1) * mDistance,
                                    getRandomFloat(0, mScale) + 1,
                                    getRandomFloat(0.1, 1) * mTotalSteps,
                                    (rand() > RAND_MAX / 2 ? imgParticle1 : imgParticle2),
                                    mColor));
        }

    }

    bool ended(){
        return !mActive;
    }

    void draw(){
        // Update the animation frame
        if (mStartTime == 0) {
            mStartTime = SDL_GetTicks();
        }

        mCurrentStep = SDL_GetTicks() - mStartTime;

        if (mCurrentStep < mTotalSteps){
            for (unsigned i = 0; i < mParticleQuantity; ++i){
                mParticleVector[i].update();
                mParticleVector[i].draw(mPosX, mPosY);
            }
        } else {
            mActive = false;
        }
    }

private:

    unsigned mParticleQuantity;

    unsigned int mStartTime;

    /// Duración del efecto
    unsigned int mTotalSteps;

    /// Posición de la animación
    unsigned int mCurrentStep;

    /// Distancia del efecto
    float mDistance;

    /// Escala de la explosión
    float mScale;

    /// Color de las partículas
    SDL_Color mColor;

    /// Contenedor para las partículas
    vector<Particle> mParticleVector;

    /// Posición donde se debe pintar
    int mPosX, mPosY;

    /// Flag que indica si el sistema de partícula está activo
    bool mActive;

};

#endif /* _PARTICULAS_H_ */
