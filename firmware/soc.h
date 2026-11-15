// Copyright (c) 2026 Tej Sanghavi.
//
// SoC memory map and peripheral register offsets. Must match
// config/socNoc.json and the PULP apb_timer / apb_gpio register maps.

#ifndef SOC_H
#define SOC_H

#include <stdint.h>

#define REG32(addr) (*(volatile uint32_t *)(addr))

// RAM (AXI4-Lite SRAM, router 1). The last word is the simulation console:
// the testbench prints every byte the CPU stores there.
#define RAM_BASE     0x00000000u
#define RAM_SIZE     0x00004000u
#define CONSOLE_ADDR 0x00003FFCu

// PULP apb_timer (router 2): two timers, 0x10 apart.
#define TIMER_BASE        0x40000000u
#define TIMER_STRIDE      0x10u
#define TIMER_COUNT(n)    REG32(TIMER_BASE + ((n) * TIMER_STRIDE) + 0x0u)
#define TIMER_CTRL(n)     REG32(TIMER_BASE + ((n) * TIMER_STRIDE) + 0x4u)
#define TIMER_CMP(n)      REG32(TIMER_BASE + ((n) * TIMER_STRIDE) + 0x8u)
#define TIMER_CTRL_ENABLE 0x1u
#define TIMER_CTRL_PRESCALER(p) (((p) & 0x7u) << 3)

// PULP apb_gpio (router 3), pads 0-31.
#define GPIO_BASE         0x40001000u
#define GPIO_DIR          REG32(GPIO_BASE + 0x00u)
#define GPIO_EN           REG32(GPIO_BASE + 0x04u)
#define GPIO_IN           REG32(GPIO_BASE + 0x08u)
#define GPIO_OUT          REG32(GPIO_BASE + 0x0Cu)
#define GPIO_OUT_SET      REG32(GPIO_BASE + 0x10u)
#define GPIO_OUT_CLR      REG32(GPIO_BASE + 0x14u)
#define GPIO_INT_EN       REG32(GPIO_BASE + 0x18u)
#define GPIO_INT_TYPE_LO  REG32(GPIO_BASE + 0x1Cu)
#define GPIO_INT_TYPE_HI  REG32(GPIO_BASE + 0x20u)
#define GPIO_INT_STATUS   REG32(GPIO_BASE + 0x24u)
#define GPIO_INT_TYPE_RISE 0x1u

// Board wiring in the testbench: pads 15:0 loop back out->in, pad 16 is the
// timer 1 compare interrupt, pads 31/30 report done/pass.
#define PAD_LOOPBACK_MASK 0x0000FFFFu
#define PAD_TIMER1_CMP    16u
#define PAD_PASS          30u
#define PAD_DONE          31u

// Address with no NoC address-map entry; the NI answers with DECERR.
#define UNMAPPED_ADDR 0x80000000u

#endif
