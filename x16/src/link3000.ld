/* One $3000 overlay: title, intro, howto, options, or game.
 * Fixed RAM ends at $9EFF; $9E00-$9EFF is the shared state page. */
__rc0 = 0x22;
INCLUDE imag-regs.ld
MEMORY { zp : ORIGIN = __rc31 + 1, LENGTH = 0x80 - (__rc31 + 1)
         ram (rw) : ORIGIN = 0x3000, LENGTH = 0x6E00 }
REGION_ALIAS("c_readonly", ram)
REGION_ALIAS("c_writeable", ram)
SECTIONS { . = ORIGIN(ram); .text : { INCLUDE text-sections.ld } > c_readonly
           INCLUDE zp.ld INCLUDE rodata.ld INCLUDE data.ld INCLUDE bss.ld INCLUDE noinit.ld }
__stack = 0x9DFF;
OUTPUT_FORMAT { SHORT(ORIGIN(ram)) TRIM(ram) }
