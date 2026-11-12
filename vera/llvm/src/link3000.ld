/* SYS stays at $2000. TITLE and GAME are independent $3000 images. */
__rc0 = 0x02;
INCLUDE imag-regs.ld
MEMORY { zp : ORIGIN = __rc31 + 1, LENGTH = 0xBF - (__rc31 + 1)
         ram (rw) : ORIGIN = 0x3000, LENGTH = 0x8800 }
REGION_ALIAS("c_readonly", ram)
REGION_ALIAS("c_writeable", ram)
SECTIONS { . = ORIGIN(ram); .text : { INCLUDE text-sections.ld } > c_readonly
           INCLUDE zp.ld INCLUDE rodata.ld INCLUDE data.ld INCLUDE bss.ld INCLUDE noinit.ld }
__stack = 0xBE00;
OUTPUT_FORMAT { SHORT(ORIGIN(ram)) SHORT(__data_end - ORIGIN(ram)) TRIM(ram) }
