#include <stdint.h>
#include "apple2e.h"

/* Original approved MUSIC.PSG stream, preloaded into auxiliary RAM. */
extern uint8_t mli_status;
extern uint8_t disk_file(const char *, uint8_t, uint16_t *, uint32_t *);
extern void disk_read(uint16_t, uint8_t *), disk_close(void);
extern void music_aux_init(void), music_aux_store(void), music_aux_page(void);
extern uint8_t music_aux_available(void);
uint8_t music_cache[256], music_page, music_aux_top;
uint8_t *music_source;
uint8_t music_destination_page;
static uint16_t psg_position, psg_size;
static uint8_t psg_ready, psg_on, cache_page;

static void clear_psg(void) {
    uint8_t n;
    VERA.address=0xF9C0; VERA.address_hi=VERA_INC_1|1;
    for(n=0;n<16;n++){VERA.data0=0;VERA.data0=0;VERA.data0=0;VERA.data0=128;}
}
void psg_restart(void) { psg_position=0; cache_page=255; }
void psg_init(void) {
    uint16_t key, blocks, n;
    uint32_t size;
    uint8_t *buffer=(uint8_t *)0x0C00;
    psg_ready=psg_on=0;
    if (!music_aux_available()) return;
    if (!disk_file("MUSIC.PSG",9,&key,&size)) return;
    if (size<3 || size>63488u) { disk_close(); return; }
    psg_size=(uint16_t)size;
    blocks=(uint16_t)((size+511u)>>9);
    music_aux_init(); music_destination_page=8;
    for(n=0;n<blocks;n++) {
        disk_read(n,buffer);
        if(mli_status){disk_close();return;}
        music_source=buffer; music_aux_store();
        music_source=buffer+256; music_aux_store();
    }
    disk_close();
    music_aux_top=music_destination_page;
    psg_ready=1; psg_restart();
}
static uint8_t event_byte(void) {
    uint8_t page,value;
    if(psg_position>=psg_size){psg_ready=0;return 0;}
    page=(uint8_t)(8u+(psg_position>>8));
    if(page!=cache_page){music_page=page;music_aux_page();cache_page=page;}
    value=music_cache[(uint8_t)psg_position];++psg_position;return value;
}
void psg_stop(void) {
    uint8_t ctrl,hi;uint16_t address;
    if(!psg_on)return;
    ctrl=VERA.control;VERA.control=0;address=VERA.address;hi=VERA.address_hi;
    clear_psg();VERA.address=address;VERA.address_hi=hi;VERA.control=ctrl;
    psg_on=0;
}
__attribute__((noinline)) void psg_tick(void) {
    uint8_t ctrl,hi,count,reg,val;uint16_t address;
    if(!psg_ready)return;
    ctrl=VERA.control;VERA.control=0;address=VERA.address;hi=VERA.address_hi;
    if(!psg_on){clear_psg();psg_restart();psg_on=1;}
    count=event_byte();
    if(count==255){clear_psg();psg_restart();count=event_byte();}
    while(count-- && psg_ready) {
        reg=event_byte();val=event_byte();
        VERA.address=(uint16_t)(0xF9C0u+reg);VERA.address_hi=1;VERA.data0=val;
    }
    VERA.address=address;VERA.address_hi=hi;VERA.control=ctrl;
}
