/* Sprite-only overlays: never erase/repaint the bitmap or a stationary gem.
 * Slot 64 mouse hand, 65 hint, 66/67 cursor/selection;
 * 68..87 digits, 88..119 particles.
 * Pristine Game Over panel ends at $18F7F; HUD begins at $1F100. */
#include <stdint.h>
#include "apple2e.h"
#include "effects.h"
#include "effects_digits.h"
#include "mouse_hand.h"
#define MOUSE_VRAM 0x1F040u
#define CURSOR_VRAM 0x19000u
#define SPARK_VRAM  0x19800u
#define FLOAT_VRAM  0x19900u
#define HINT_VRAM   0x1CC40u
#define FLOATS 4
#define SPARKS 32
#define FLOAT_FIRST 68u
#define SPARK_FIRST 88u
static uint8_t age[FLOATS], spark_age[SPARKS], float_next, spark_next;
static uint8_t float_digits[FLOATS];
static uint16_t fx[FLOATS];
static int16_t fy[FLOATS], px[SPARKS], py[SPARKS];
static int8_t vx[SPARKS], vy[SPARKS];
static uint8_t hint_age;
static void at(uint32_t a){VERA.control=0;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;}
static void hide(uint8_t slot){at(0x1FC06u+(uint16_t)slot*8u);VERA.data0=0;}
static void sprite(uint8_t slot,uint32_t pattern,int16_t x,int16_t y,uint8_t size){
    at(0x1FC00u+(uint16_t)slot*8u);
    VERA.data0=(uint8_t)(pattern>>5);VERA.data0=(uint8_t)((pattern>>13)|(slot==EFFECT_MOUSE_SLOT?0:0x80u));
    VERA.data0=(uint8_t)x;VERA.data0=(uint8_t)((uint16_t)x>>8);
    VERA.data0=(uint8_t)y;VERA.data0=(uint8_t)((uint16_t)y>>8);
    VERA.data0=0x0C;VERA.data0=size;
}
static void position(uint8_t slot,int16_t x,int16_t y){
    at(0x1FC02u+(uint16_t)slot*8u);
    VERA.data0=(uint8_t)x;VERA.data0=(uint8_t)((uint16_t)x>>8);
    VERA.data0=(uint8_t)y;VERA.data0=(uint8_t)((uint16_t)y>>8);
}
void effects_clear(void){
    uint8_t n;
    for(n=0;n<FLOATS;n++)age[n]=0;
    for(n=0;n<SPARKS;n++)spark_age[n]=0;
    for(n=65;n<120;n++)hide(n);
    hint_age=0;
    float_next=spark_next=0;
}
void effects_init(void){
    uint16_t i;uint8_t n,x,y,green=11,best=255;
    /* Cyan outer frame and white selected-cell inner corner brackets. */
    at(CURSOR_VRAM);
    for(n=0;n<2;n++)for(y=0;y<32;y++)for(x=0;x<32;x++){
        uint8_t ink=0;
        if(!n && x>=3 && x<=28 && y>=3 && y<=28 && (x==3||x==28||y==3||y==28))ink=10;
        if(n && x>=4 && x<=27 && y>=4 && y<=27 &&
            (((x==4||x==27)&&(y<10||y>21))||((y==4||y==27)&&(x<10||x>21))))ink=11;
        VERA.data0=ink;
    }
    /* Four shrinking star patterns. Each is 8x8 / 64 bytes. */
    at(SPARK_VRAM);
    for(n=0;n<4;n++)for(y=0;y<8;y++)for(x=0;x<8;x++){
        int8_t dx=(int8_t)x-3,dy=(int8_t)y-3;
        uint8_t radius=(uint8_t)(3u-n),ink=0;
        if((dx==0 && dy>=-(int8_t)radius && dy<=(int8_t)radius)||
           (dy==0 && dx>=-(int8_t)radius && dx<=(int8_t)radius))ink=11;
        VERA.data0=ink;
    }
    at(FLOAT_VRAM);
    for(i=0;i<sizeof(effects_digits);i++)VERA.data0=effects_digits[i];
    at(MOUSE_VRAM);
    for(i=0;i<sizeof(mouse_hand);i++)VERA.data0=mouse_hand[i];
    /* Choose existing green ink without altering the artwork palette. */
    at(0x1FA00u);
    for(i=0;i<256;i++){
        uint8_t gb=VERA.data0,r=VERA.data0;
        uint8_t distance=(uint8_t)((r&15u)+(gb&15u)+15u-(gb>>4));
        if(i && distance<best){best=distance;green=(uint8_t)i;}
    }
    at(HINT_VRAM);
    for(n=0;n<3;n++)for(y=0;y<32;y++)for(x=0;x<32;x++){
        uint8_t edge=(uint8_t)(2u-n),far=(uint8_t)(31u-edge);
        VERA.data0=x>=edge&&x<=far&&y>=edge&&y<=far&&
            (x==edge||x==far||y==edge||y==far)?green:0;
    }
    effects_clear();
}
void effects_hide_hint(void){hint_age=0;hide(EFFECT_HINT_SLOT);}
void effects_mouse(uint16_t x,uint8_t y){sprite(EFFECT_MOUSE_SLOT,MOUSE_VRAM,(int16_t)x,(int16_t)y,0x50);}
void effects_hint(uint8_t x,uint8_t y){
    hint_age=1;
    /* Render before cursors and effects. At 32px height / 26px pitch,
       two rows of gems consume 640 of VERA's 800 scanline clocks. A late
       slot can run out of clocks partway across the hint's right edge. */
    sprite(EFFECT_HINT_SLOT,HINT_VRAM,(int16_t)(93u+x*26u),(int16_t)(13u+y*26u),0xA0);
}
void effects_cursor(uint8_t x,uint8_t y,uint8_t selected,uint8_t sx,uint8_t sy){
    sprite(EFFECT_CURSOR_SLOT,CURSOR_VRAM,(int16_t)(93u+x*26u),(int16_t)(13u+y*26u),0xA0);
    if(selected)sprite(EFFECT_SELECTION_SLOT,CURSOR_VRAM+1024u,(int16_t)(93u+sx*26u),(int16_t)(13u+sy*26u),0xA0);
    else hide(EFFECT_SELECTION_SLOT);
}
static void floating(uint16_t value,uint16_t center_x,uint16_t center_y){
    uint8_t s[5],count=0,n,slot=float_next;
    do{s[count++]=(uint8_t)(value%10u);value/=10u;}while(value && count<5);
    for(n=0;n<5;n++)hide((uint8_t)(FLOAT_FIRST+slot*5u+n));
    fx[slot]=center_x-count*6u-2u;
    if(fx[slot]<94u)fx[slot]=94u;
    if(fx[slot]>288u-(count-1u)*12u)fx[slot]=288u-(count-1u)*12u;
    fy[slot]=(int16_t)center_y-8;age[slot]=1;
    float_digits[slot]=count;
    for(n=0;n<count;n++)sprite((uint8_t)(FLOAT_FIRST+slot*5u+n),FLOAT_VRAM+(uint16_t)s[count-1u-n]*256u,(int16_t)(fx[slot]+n*12u),fy[slot],0x50);
    float_next=(uint8_t)((slot+1u)&3u);
}
void effects_matches(const Board *b,const uint8_t marks[8][8],uint8_t points,uint8_t multiplier){
    uint8_t x,y,start,gem,n,slot;
    uint16_t value;
    /* Same maximal H/V groups as board_score_matches (cross counts twice). */
    for(y=0;y<8;y++)for(x=0;x<8;){start=x;gem=b->cells[y][x];while(x<8 && b->cells[y][x]==gem)++x;
        if(x-start>=3){value=(uint16_t)(x-start)*points*multiplier;floating(value,(uint16_t)(109u+(start+x-1u)*13u),(uint16_t)(29u+y*26u));}}
    for(x=0;x<8;x++)for(y=0;y<8;){start=y;gem=b->cells[y][x];while(y<8 && b->cells[y][x]==gem)++y;
        if(y-start>=3){value=(uint16_t)(y-start)*points*multiplier;floating(value,(uint16_t)(109u+x*26u),(uint16_t)(29u+(start+y-1u)*13u));}}
    /* Four radial sparks per removed gem, bounded ring pool on 6502. */
    for(y=0;y<8;y++)for(x=0;x<8;x++)if(marks[y][x])for(n=0;n<4;n++){
        slot=spark_next;spark_next=(uint8_t)((slot+1u)&31u);
        px[slot]=(int16_t)(105u+x*26u);py[slot]=(int16_t)(25u+y*26u);
        vx[slot]=(n&1u)?1:-1;vy[slot]=(n&2u)?1:-1;spark_age[slot]=1;
        sprite((uint8_t)(SPARK_FIRST+slot),SPARK_VRAM,px[slot],py[slot],0);
    }
}
void effects_tick(void){
    uint8_t n,a,d;
    if(hint_age){
        a=hint_age++;
        if(a>=40)effects_hide_hint();
        else if(a==13||a==26){
            uint32_t pattern=HINT_VRAM+(uint16_t)(a/13u)*1024u;
            at(0x1FC00u+EFFECT_HINT_SLOT*8u);
            VERA.data0=(uint8_t)(pattern>>5);VERA.data0=(uint8_t)((pattern>>13)|0x80u);
        }
    }
    for(n=0;n<FLOATS;n++)if((a=age[n])!=0){
        if(a>=50){age[n]=0;for(d=0;d<float_digits[n];d++)hide((uint8_t)(FLOAT_FIRST+n*5u+d));}
        else{age[n]=a+1;if(a%3u==0){int16_t y=fy[n]-(int16_t)(a/3u);if(y<16)y=16;
            for(d=0;d<float_digits[n];d++)position((uint8_t)(FLOAT_FIRST+n*5u+d),(int16_t)(fx[n]+d*12u),y);}}
    }
    for(n=0;n<SPARKS;n++)if((a=spark_age[n])!=0){
        if(a>=20){spark_age[n]=0;hide((uint8_t)(SPARK_FIRST+n));}
        else{spark_age[n]=a+1;if(a<12){px[n]+=vx[n];py[n]+=vy[n];}
            if(a==5||a==10||a==15)sprite((uint8_t)(SPARK_FIRST+n),SPARK_VRAM+(uint16_t)(a/5u)*64u,px[n],py[n],0);
            else if(a<12)position((uint8_t)(SPARK_FIRST+n),px[n],py[n]);}
    }
}
