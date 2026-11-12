#include <stdint.h>
#include "apple2e.h"
#include "random_seed.h"

static void puts(const char *s) {
    while (*s) x16_kputc((uint8_t)*s++);
}

int main(void) {
    uint16_t i;
    uint8_t f;
    x16_kputc(0x93); /* PETSCII clear screen */
    puts("FREEGEMAS FOR COMMANDER X16\r");
    puts("BY ANOMIXER 2026\r");
    puts("HTTPS://GITHUB.COM/ANOMIXER/FREEGEMAS\r");
    puts("---------------------------------------\r");
    puts("STATUS: VERA AT $9F20\r");
    puts("AUDIO: ZCM MUSIC + PCM EFFECTS\r");
    puts("INPUT: CURSOR JOY + KEYS\r");
    puts("CONTROLS:\r");
    puts("  ARROW KEYS   : MOVE / MENU SELECT\r");
    puts("  SPACE        : SELECT / SWAP GEMS\r");
    puts("  ENTER        : CONFIRM MENU ITEM\r");
    puts("  H            : SHOW HINT\r");
    puts("  R            : RESET / RESHUFFLE\r");
    puts("  ESC          : RETURN TO TITLE\r");
    puts("  TITLE EXIT   : QUIT TO BASIC\r");
    puts("HIT ANY KEY OR WAIT 1 SEC TO START...\r");
    kbd_clear();
    for (i = 0; i < 60; ++i) {
        f = X16_FRAME;
        random_poll();
        if (kbd_pressed()) break;
        while (X16_FRAME == f) {}
        random_poll();
    }
    kbd_clear();
    NEXT_IMAGE = 0;
    ((void (*)(void))0x2000)();
    return 0;
}
