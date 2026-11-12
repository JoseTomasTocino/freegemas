#include <stdint.h>
#include "apple2e.h"
#include "title_palette.h"
#include "title_gems.h"
#include "random_seed.h"
#include "menu_mouse.h"

#define NEXT_IMAGE (*(volatile uint8_t *)0x03F0)
#define LOAD_GAME_MAGIC 0xA5u
#define LOAD_HOWTO_MAGIC 0xA6u
#define LOAD_OPTIONS_MAGIC 0xA7u
#define QUIT_MAGIC 0xA8u
#define GAME_MODE (*(volatile uint8_t *)0x03F1)
#define TITLE_GEMS_VRAM 0x12C00u
#define TITLE_GEM_Y 104u
#define TITLE_MENU_Y 144u

static uint8_t marker_bg[5][49];
static void at(uint32_t a){VERA.control=0;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;}
static void at1(uint32_t a){VERA.control=1;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;VERA.control=0;}
static void waitvsync(void){while(!(VERA.irq_flags&VERA_IRQ_VSYNC)){random_poll();}random_poll();VERA.irq_flags=VERA_IRQ_VSYNC;}
static void sprite(uint8_t slot,uint8_t gem,uint16_t x,uint16_t y,uint8_t visible){
    uint32_t p=TITLE_GEMS_VRAM+(uint32_t)gem*1024u;
    at(0x1FC00u+(uint32_t)slot*8u);
    VERA.data0=(uint8_t)(p>>5);VERA.data0=(uint8_t)((p>>13)|0x80u);
    VERA.data0=(uint8_t)x;VERA.data0=(uint8_t)(x>>8);VERA.data0=(uint8_t)y;VERA.data0=(uint8_t)(y>>8);
    VERA.data0=visible?0x0Cu:0;VERA.data0=0xA0;
}
static void animate_gems(void){
    uint8_t frame,g;
    for(frame=0;frame<=60;frame++){
        for(g=0;g<7;g++){
            int8_t step=(int8_t)frame-(int8_t)(g*5u);
            if(step<0)sprite(g,g,0,0,0);
            else{
                uint8_t s=(uint8_t)step>30u?30u:(uint8_t)step;
                uint32_t remain=(uint32_t)(30u-s);
                uint16_t y=(uint16_t)(TITLE_GEM_Y+((237u-TITLE_GEM_Y)*remain*remain*remain)/27000u);
                sprite(g,g,(uint16_t)(69u+g*26u),y,1);
            }
        }
        waitvsync();
    }
}
static void cache_markers(void){uint8_t item,r,c;for(item=0;item<5;item++)for(r=0;r<7;r++){at1((uint32_t)(TITLE_MENU_Y+item*17u+r)*320u+110u);for(c=0;c<7;c++)marker_bg[item][r*7u+c]=VERA.data1;}}
static void marker(uint8_t item,uint8_t on){uint8_t y=(uint8_t)(TITLE_MENU_Y+item*17u),r,c;for(r=0;r<7;r++){at((uint32_t)(y+r)*320u+110u);for(c=0;c<7;c++)VERA.data0=on&&c<=r&&c<=6-r?255:marker_bg[item][r*7u+c];}}

int main(void){
    uint16_t i;uint8_t selected=0;
    VERA.control=0;VERA.display.video=0;VERA.display.hscale=0x40;VERA.display.vscale=0x40;
    VERA.layer0.config=7;VERA.layer0.mapbase=0;VERA.layer0.tilebase=0;
    VERA.layer0.hscroll=0;VERA.layer0.vscroll=0;
    at(0x1FA00u);for(i=0;i<sizeof(title_palette);i++)VERA.data0=title_palette[i];
    at(TITLE_GEMS_VRAM);for(i=0;i<sizeof(title_gems);i++)VERA.data0=title_gems[i];
    for(i=0;i<128;i++)sprite((uint8_t)i,0,0,0,0);
    VERA.display.video=0x51;cache_markers();marker(selected,1);animate_gems();
    menu_mouse_init();
    for(;;){
        /* Polling count captures the player's menu timing, including returns
           from a previous game; do not restart a fixed RNG sequence. */
        RANDOM_SEED=(uint16_t)(RANDOM_SEED+1u);
        random_poll();
        uint8_t click=menu_mouse_update(),k=0;
        if(click && mouse_x>=110u && mouse_x<230u && mouse_y>=140u && mouse_y<225u){
            uint8_t item=(uint8_t)((mouse_y-140u)/17u);
            if(item!=selected){marker(selected,0);selected=item;marker(selected,1);}
            if(click&1u)k=0x0D;
        }
        if(kbd_pressed()){k=kbd_read();kbd_clear();}
        if(k){
        if(k==0x08||k==0x0B){marker(selected,0);selected=selected?selected-1:4;marker(selected,1);}
        else if(k==0x15||k==0x0A){marker(selected,0);selected=(uint8_t)((selected+1)%5);marker(selected,1);}
        else if(k==0x20||k==0x0D){if(selected<2){GAME_MODE=selected;NEXT_IMAGE=LOAD_GAME_MAGIC;}else if(selected==2){NEXT_IMAGE=LOAD_HOWTO_MAGIC;}else if(selected==3){NEXT_IMAGE=LOAD_OPTIONS_MAGIC;}else{NEXT_IMAGE=QUIT_MAGIC;}((void(*)(void))0x2000)();}
        }
    }
}
