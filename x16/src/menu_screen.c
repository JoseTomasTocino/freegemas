#include <stdint.h>
#include "apple2e.h"
#include "title_palette.h"
#include "hiscore.h"
#include "menu_mouse.h"
static uint8_t bg[4][49];
static void waitvsync(void){uint8_t f=X16_FRAME;while(X16_FRAME==f){}}
/* The key that chose this screen may still be held or queued.  Drain KERNAL
 * GETIN and the local ring for half a second so the transition key cannot
 * immediately close How to Play / Options. */
static void settle(void){uint8_t n;for(n=0;n<30;n++){x16_kgetin();kbd_clear();waitvsync();}}
static void at(uint32_t a){VERA.control=0;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;}
static void at1(uint32_t a){VERA.control=1;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;VERA.control=0;}
static void back(void){NEXT_IMAGE=0;((void(*)(void))0x2000)();}
#ifdef OPTIONS_SCREEN
static uint8_t value_bg[2][504];
static uint8_t music_on=1,sound_on=1;
static void records(void){
    static const uint8_t digits[10][7]={{14,17,19,21,25,17,14},{4,12,4,4,4,4,14},{14,17,1,2,4,8,31},{30,1,1,14,1,1,30},{2,6,10,18,31,2,2},{31,16,16,30,1,1,30},{14,16,16,30,17,17,14},{31,1,2,4,8,8,8},{14,17,17,14,17,17,14},{14,17,17,15,1,1,14}};
    static const uint8_t letters[14][7]={
        {31,4,4,4,4,4,4},{4,0,12,4,4,4,14},{0,0,26,21,21,21,21},
        {0,0,14,17,31,16,14},{0,0,22,25,16,16,16},{0,0,14,1,15,17,15},
        {12,4,4,4,4,4,14},{0,4,4,0,4,4,0},{0,0,30,17,17,17,17},
        {1,1,15,17,17,17,15},{0,0,15,16,14,1,30},{0,0,0,0,0,0,0},
        {31,16,16,30,16,16,31},{4,4,31,4,4,5,2}};
    static const uint8_t labels[2][10]={{0,1,2,3,13,4,1,5,6,7},{12,8,9,6,3,10,10,11,11,7}};
    uint8_t n,r,c,p,width=0,x;uint32_t v;uint8_t s[2][10],count[2]={0,0};
    for(n=0;n<2;n++){v=HIGH_SCORES[n];do{s[n][count[n]++]=(uint8_t)(v%10);v/=10;}while(v);if(count[n]>width)width=count[n];}
    x=(uint8_t)((320u-((11u+width)*6u-1u))/2u);
    for(n=0;n<2;n++){
        for(p=0;p<10;p++)for(r=0;r<7;r++)for(c=0;c<5;c++)if(letters[labels[n][p]][r]&(16u>>c)){at((uint32_t)(171u+n*14u+r)*320u+x+p*6u+c);VERA.data0=255;}
        for(p=0;p<count[n];p++)for(r=0;r<7;r++)for(c=0;c<5;c++)if(digits[s[n][count[n]-1-p]][r]&(16u>>c)){at((uint32_t)(171u+n*14u+r)*320u+x+(11u+width-count[n]+p)*6u+c);VERA.data0=255;}
    }
}
static void cache(void){uint8_t n,r,c;for(n=0;n<4;n++)for(r=0;r<7;r++){at1((uint32_t)(64u+n*17u+r)*320u+66u);for(c=0;c<7;c++)bg[n][r*7u+c]=VERA.data1;}}
static void mark(uint8_t n,uint8_t on){uint8_t r,c;for(r=0;r<7;r++){at((uint32_t)(64u+n*17u+r)*320u+66u);for(c=0;c<7;c++)VERA.data0=on&&c<=r&&c<=6-r?255:bg[n][r*7u+c];}}
static uint8_t glyph(uint8_t ch,uint8_t r){
    static const uint8_t o[7]={14,17,17,17,17,17,14},n[7]={0,0,30,17,17,17,17},f[7]={6,8,28,8,8,8,8};
    static const uint8_t p[7]={30,17,17,30,16,16,16},c[7]={14,17,16,16,16,17,14};
    static const uint8_t m[7]={17,27,21,21,17,17,17},s[7]={15,16,16,14,1,1,30},z[7]={31,1,2,4,8,16,31},g[7]={14,17,16,23,17,17,15};
    switch(ch){case 'O':return o[r];case 'n':return n[r];case 'f':return f[r];case 'P':return p[r];case 'C':return c[r];case 'M':return m[r];case 'S':return s[r];case 'Z':return z[r];default:return g[r];}
}
static void cache_values(void){uint8_t n,r,c;for(n=0;n<2;n++)for(r=0;r<14;r++){at1((uint32_t)(60u+n*17u+r)*320u+188u);for(c=0;c<36;c++)value_bg[n][r*36u+c]=VERA.data1;}}
static void value(uint8_t n,uint8_t on){uint8_t r,c,ch,px,py;const char *s=n==0?(on?"ZCM":"Off"):(on?"On":"Off");for(r=0;r<14;r++){at((uint32_t)(60u+n*17u+r)*320u+188u);for(c=0;c<36;c++)VERA.data0=value_bg[n][r*36u+c];}for(ch=0;s[ch];ch++)for(r=0;r<7;r++)for(c=0;c<5;c++)if(glyph((uint8_t)s[ch],r)&(uint8_t)(16u>>c))for(py=0;py<2;py++)for(px=0;px<2;px++){at((uint32_t)(60u+r*2u+py+n*17u)*320u+190u+ch*12u+c*2u+px);VERA.data0=255;}}
#endif
int main(void){uint16_t i;uint8_t selected=0;VERA.control=0;VERA.display.video=0;VERA.display.hscale=0x40;VERA.display.vscale=0x40;VERA.layer0.config=7;VERA.layer0.mapbase=0;VERA.layer0.tilebase=0;at(0x1FA00u);for(i=0;i<sizeof(title_palette);i++)VERA.data0=title_palette[i];
#ifdef OPTIONS_SCREEN
records();
#endif
VERA.layer0.hscroll=0;VERA.layer0.vscroll=0;
VERA.display.video=0x11;
/* Scene transitions must not inherit game/title gem sprites. */
at(0x1FC00u);for(i=0;i<1024;i++)VERA.data0=0;
menu_mouse_init();
#ifdef OPTIONS_SCREEN
if(MUSIC_SETTING>1)MUSIC_SETTING=1;if(SOUND_SETTING>1)SOUND_SETTING=1;music_on=MUSIC_SETTING;sound_on=SOUND_SETTING;cache();cache_values();value(0,music_on);value(1,sound_on);mark(0,1);settle();
for(;;){
    uint8_t k=0,click=menu_mouse_update();
    if(click && mouse_x>=66u && mouse_x<250u && mouse_y>=60u && mouse_y<128u){
        uint8_t item=(uint8_t)((mouse_y-60u)/17u);
        if(item!=selected){mark(selected,0);selected=item;mark(selected,1);}
        if(click&1u)k=0x0D;
    }
    if(kbd_pressed()){k=kbd_read();kbd_clear();}
    if(k==0x1B)back();
    else if(k==0x08||k==0x0B){mark(selected,0);selected=selected?selected-1:3;mark(selected,1);}
    else if(k==0x15||k==0x0A){mark(selected,0);selected=(uint8_t)((selected+1u)&3u);mark(selected,1);}
    else if(k==0x20||k==0x0D){
        if(selected==0){music_on=music_on?0:1;MUSIC_SETTING=music_on;value(0,music_on);}
        else if(selected==1){sound_on=!sound_on;SOUND_SETTING=sound_on;value(1,sound_on);}
        else if(selected==3)back();
    }
}
#else
settle();
for(;;){if(menu_mouse_update()&1u)back();if(kbd_pressed()){kbd_clear();back();}}
#endif
}
