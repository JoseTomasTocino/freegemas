#ifndef RANDOM_SEED_H
#define RANDOM_SEED_H
#include <stdint.h>
/* Survives $3000 segment reloads; separate from score/settings state. */
#define RANDOM_SEED (*(volatile uint16_t *)0x03EA)
/* Capture key arrival even while startup/title animations are still running.
   Keeping a constant number of animation frames alone supplies no entropy. */
static uint16_t random_ticks;
static uint8_t random_key_down;
static void random_poll(void){
    uint16_t t=++random_ticks;
    if((*(volatile uint8_t *)0xC000)&0x80u){
        if(!random_key_down){
            uint16_t seed=RANDOM_SEED;
            RANDOM_SEED=(uint16_t)(((seed<<5)|(seed>>11))^t^(t<<7)^0x9E37u);
            random_key_down=1;
        }
    }else random_key_down=0;
}
#endif
