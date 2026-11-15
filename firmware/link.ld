/* Copyright (c) 2026 Tej Sanghavi.
 *
 * 16 KiB RAM at 0x0: code and data in the low 12 KiB, stack grows down from
 * 0x3FF0, the console mailbox is the last word (0x3FFC).
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
  RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 0x3000
}

_stack_top = 0x3FF0;

SECTIONS
{
  .text : {
    *(.text.start)
    *(.text .text.*)
  } > RAM

  .rodata : {
    *(.rodata .rodata.* .srodata .srodata.*)
  } > RAM

  .data : {
    *(.data .data.* .sdata .sdata.*)
  } > RAM

  .bss (NOLOAD) : {
    . = ALIGN(4);
    _bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(4);
    _bss_end = .;
  } > RAM

  /DISCARD/ : { *(.comment) *(.riscv.attributes) }
}
