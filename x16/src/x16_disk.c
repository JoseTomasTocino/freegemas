#include <stdint.h>
#include "apple2e.h"

/* Assets are loaded from the SD/HostFS as 8000-byte chunks into banked RAM
 * banks 30..39.  The game then consumes them through the original 512-byte
 * block interface, so scene RLE decoding and PCM effect loading stay intact. */
#define DISK_BASE_BANK 30u
#define DISK_CHUNK     8000u
#define DISK_MAX_CHUNKS 10u

uint8_t mli_status;
static uint32_t disk_size;
static uint8_t disk_open;
static uint8_t disk_epoch_value;

uint8_t disk_epoch(void) { return disk_epoch_value; }

static void make_plain_name(const char *name, uint8_t len) {
    uint8_t i;
    for (i = 0; i < len; ++i) {
        uint8_t c = (uint8_t)name[i];
        if (c >= 'A' && c <= 'Z') c = (uint8_t)(c + 32);
        x16_name[i] = c;
    }
    x16_namelen = len;
}

static void make_name(const char *name, uint8_t len, uint8_t index) {
    make_plain_name(name, len);
    x16_name[len] = '.';
    x16_name[len + 1] = (uint8_t)('0' + index);
    x16_namelen = (uint8_t)(len + 2u);
}

void disk_close(void) {
    disk_open = 0;
}

uint8_t disk_file(const char *name, uint8_t len, uint16_t *key, uint32_t *size) {
    uint32_t total = 0;
    uint8_t index = 0;
    disk_close();
    mli_status = 0;
    while (index < DISK_MAX_CHUNKS) {
        uint16_t n;
        x16_sa = 2;
        x16_mode = 0;
        x16_bank = (uint8_t)(DISK_BASE_BANK + index);
        x16_addr = 0xA000u;
        make_name(name, len, index);
        x16_kload();
        if (x16_err && index == 0) {
            /* Small assets are shipped as a single unsuffixed file. */
            make_plain_name(name, len);
            x16_kload();
        }
        if (x16_err) {
            if (index == 0) return 0;
            break;
        }
        if (x16_end < 0xA000u) return 0;
        n = (uint16_t)(x16_end - 0xA000u);
        if (n > DISK_CHUNK) return 0;
        total += n;
        ++index;
        if (n < DISK_CHUNK) break;
    }
    if (!index || !total) return 0;
    disk_size = total;
    disk_open = 1;
    ++disk_epoch_value;
    *key = 0;
    *size = total;
    return 1;
}

void disk_read(uint16_t block, uint8_t *dest) {
    uint32_t offset = (uint32_t)block << 9;
    uint16_t count;
    if (!disk_open || offset >= disk_size) { mli_status = 0x4C; return; }
    count = disk_size - offset > 512u ? 512u : (uint16_t)(disk_size - offset);
    while (count) {
        uint32_t chunk = offset / DISK_CHUNK;
        uint16_t in = (uint16_t)(offset % DISK_CHUNK);
        uint16_t take = (uint16_t)(DISK_CHUNK - in);
        uint16_t i;
        volatile uint8_t *src;
        if (take > count) take = count;
        *(volatile uint8_t *)0x00 = (uint8_t)(DISK_BASE_BANK + chunk);
        src = (volatile uint8_t *)(0xA000u + in);
        for (i = 0; i < take; ++i) *dest++ = src[i];
        offset += take;
        count = (uint16_t)(count - take);
    }
    *(volatile uint8_t *)0x00 = X16_HUD_BANK;
    mli_status = 0;
}
