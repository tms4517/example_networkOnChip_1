// Copyright (c) 2026 Tej Sanghavi.
//
// Reset entry: the CPU starts here at address 0 (PROGADDR_RESET). The image
// is preloaded into RAM so .data needs no copy; only .bss is cleared.

  .section .text.start
  .global _start
_start:
  la    sp, _stack_top
  la    t0, _bss_start
  la    t1, _bss_end
clear_bss:
  bgeu  t0, t1, run_main
  sw    zero, 0(t0)
  addi  t0, t0, 4
  j     clear_bss
run_main:
  call  main
halt:
  j     halt
