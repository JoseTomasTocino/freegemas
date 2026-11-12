#include <stdint.h>
#include "apple2e.h"
#include "random_seed.h"
#define DETECTED_VERA (*(volatile uint8_t *)0x03EC)

static void line(uint8_t row,const char *s){
    volatile uint8_t *p=(volatile uint8_t *)(0x400u+(row&7u)*128u+(row>>3)*40u);
    while(*s)*p++=(uint8_t)(*s++|0x80u);
}
/* Signature-only detection: do not initialize firmware or overwrite text
 * screen holes while showing the introduction. */
static uint8_t mouse_detect(void){
    uint8_t slot;
    for(slot=4;slot<=5;slot++){
#if VERA_BASE == 0xC400
        if(slot==4)continue;
#endif
        volatile uint8_t *rom=(volatile uint8_t *)(0xC000u+(uint16_t)slot*256u);
        if(rom[0x0C]==0x20 && rom[0xFB]==0xD6)return slot;
    }
    return 0;
}

#include "fm_probe.h"
/* YM2151 presence is informational only: the music is streamed PCM. */
static uint8_t fm_detect(void){
    volatile uint8_t *scratch=(volatile uint8_t *)0x0300;
    uint8_t i;
    for(i=0;i<sizeof(fm_probe);i++)scratch[i]=fm_probe[i];
    ((void(*)(void))0x0300)();
    return *(volatile uint8_t *)0x02FF;
}
int main(void){
    uint16_t i;
    uint8_t mouse=mouse_detect();
    if(DETECTED_VERA){VERA.control=0;VERA.display.video=0;}
    *(volatile uint8_t *)0xC00C=0;*(volatile uint8_t *)0xC00E=0;
    *(volatile uint8_t *)0xC051=0;*(volatile uint8_t *)0xC054=0;
    for(i=0;i<1024;i++)((volatile uint8_t *)0x400)[i]=0xA0;
    line(0,"FREEGEMAS FOR APPLE II VERA");
    line(1,"BY ANOMIXER 2026");
    line(2,"HTTPS://GITHUB.COM/ANOMIXER/FREEGEMAS");
    line(3,"---------------------------------------");
    if(!DETECTED_VERA)line(5,"STATUS: VERA NOT DETECTED");
    else {
#if VERA_BASE == 0xC400
    line(5,"STATUS: VERA CARD DETECTED IN SLOT 4");
#else
    line(5,"STATUS: VERA CARD DETECTED IN SLOT 2");
#endif
    line(4,fm_detect()?"FM: YM2151 DETECTED (OPM)":"FM: NONE");
    }
    line(6,mouse==4?"MOUSE: SLOT 4":mouse==5?"MOUSE: SLOT 5":"MOUSE: NONE");
    line(7,"CONTROLS:");
    line(9,"  ARROW KEYS   : MOVE / MENU SELECT");
    line(10,"  SPACE        : SELECT / SWAP GEMS");
    line(11,"  ENTER        : CONFIRM MENU ITEM");
    line(12,"  H            : SHOW HINT");
    line(13,"  R            : RESET / RESHUFFLE");
    line(14,"  ESC          : RETURN TO TITLE");
    line(15,"  TITLE EXIT   : QUIT TO PRODOS");
    line(16,"  MOUSE        : CLICK / DRAG GEMS");
    if(!DETECTED_VERA){
        line(18,"STOPPED: VERA REQUIRED IN SLOT 2 OR 4");
        for(;;){}
    }
    line(18,"HIT ANY KEY OR WAIT 5 SECS TO START...");
    kbd_clear();
    for(i=0;i<300;i++){
        random_poll();
        if(kbd_pressed())break;
        VERA.irq_flags=VERA_IRQ_VSYNC;
        while(!(VERA.irq_flags&VERA_IRQ_VSYNC)){random_poll();if(kbd_pressed())break;}
    }
    kbd_clear();
    for(i=0;i<1024;i++)((volatile uint8_t *)0x400)[i]=0xA0;
    *(volatile uint8_t *)0x03F0=0;
    ((void(*)(void))0x2000)();
    return 0;
}
