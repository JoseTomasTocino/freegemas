#include <stdint.h>
#include "apple2e.h"
#include "menu_mouse.h"
#include "mouse_hand.h"
#include "title_palette.h"
static uint8_t was_down;
static uint16_t last_x;
static uint8_t last_y;
static void at(uint32_t a){VERA.control=0;VERA.address_hi=(uint8_t)(VERA_INC_1|(a>>16));VERA.address=(uint16_t)a;}
void menu_mouse_init(void){
    uint16_t i;uint8_t black=0;uint16_t best=0xFFFF;
    if(!mouse_init())return;
    for(i=1;i<256;i++){
        uint16_t v=(title_palette[i*2]&15)+(title_palette[i*2]>>4)+(title_palette[i*2+1]&15);
        if(v<best){best=v;black=(uint8_t)i;}
    }
    at(0x1F040u);
    for(i=0;i<sizeof(mouse_hand);i++){
        uint8_t p=mouse_hand[i],a=p>>4,b=p&15;
        VERA.data0=a==11?255:a?black:0;
        VERA.data0=b==11?255:b?black:0;
    }
    mouse_poll();was_down=(mouse_buttons&128u)!=0;
    last_x=mouse_x;last_y=mouse_y;
    VERA.display.video|=0x40;
    VERA.irq_flags=VERA_IRQ_VSYNC;
}
uint8_t menu_mouse_update(void){
    uint8_t down,pressed,moved;
    if(!mouse_slot || !(VERA.irq_flags&VERA_IRQ_VSYNC))return 0;
    VERA.irq_flags=VERA_IRQ_VSYNC;mouse_poll();
    down=(mouse_buttons&128u)!=0;pressed=down&&!was_down;was_down=down;
    moved=mouse_x!=last_x || mouse_y!=last_y;last_x=mouse_x;last_y=mouse_y;
    at(0x1FC00u+64u*8u);
    VERA.data0=0x82;VERA.data0=0x8F;
    VERA.data0=(uint8_t)mouse_x;VERA.data0=(uint8_t)(mouse_x>>8);
    VERA.data0=mouse_y;VERA.data0=0;VERA.data0=12;VERA.data0=0x50;
    return pressed | (moved?2u:0u);
}
