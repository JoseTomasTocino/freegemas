/* Resident loader at $2000, must stay below the independently loaded $3000
 * overlays.  It keeps the KERNAL IRQ chain and the high-score code. */
__rc0 = 0x22;
INCLUDE imag-regs.ld
MEMORY { zp : ORIGIN = __rc31 + 1, LENGTH = 0x80 - (__rc31 + 1)
         ram (rw) : ORIGIN = 0x2000, LENGTH = 0x1000 }
REGION_ALIAS("c_readonly", ram)
REGION_ALIAS("c_writeable", ram)
SECTIONS { . = ORIGIN(ram); .text : { INCLUDE text-sections.ld } > c_readonly
           INCLUDE zp.ld INCLUDE rodata.ld INCLUDE data.ld INCLUDE bss.ld INCLUDE noinit.ld }
__stack = 0x9DFF;
OUTPUT_FORMAT { SHORT(ORIGIN(ram)) TRIM(ram) }
