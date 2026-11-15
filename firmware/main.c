// Copyright (c) 2026 Tej Sanghavi.
//
// Boot firmware for the networkOnChip demo SoC. Every access below travels
// from the PicoRV32 through the NoC: RAM over AXI4-Lite, the timer and GPIO
// over the NoC's AXI4-Lite to APB target bridges. Each check is printed on
// the console; the result is reported on GPIO pads 31 (done) and 30 (pass).
//
// RV32I without libgcc: no multiply/divide is used.

#include <stdint.h>
#include "soc.h"

static uint32_t errors;
static volatile uint32_t scratch[4];

static void putChar(char c)
{
  *(volatile uint8_t *)CONSOLE_ADDR = (uint8_t)c;
}

static void putStr(const char *s)
{
  while (*s)
    putChar(*s++);
}

static void putHex(uint32_t value)
{
  putStr("0x");
  for (int shift = 28; shift >= 0; shift -= 4)
    putChar("0123456789abcdef"[(value >> shift) & 0xFu]);
}

static void check(const char *name, uint32_t got, uint32_t expected)
{
  putStr(got == expected ? "  [ OK ] " : "  [FAIL] ");
  putStr(name);
  putStr(" = ");
  putHex(got);
  if (got != expected) {
    errors++;
    putStr(" expected ");
    putHex(expected);
  }
  putChar('\n');
}

static void delay(uint32_t iterations)
{
  for (volatile uint32_t i = 0; i < iterations; i++)
    ;
}

static void testRam(void)
{
  volatile uint8_t *bytes = (volatile uint8_t *)scratch;
  volatile uint16_t *halves = (volatile uint16_t *)scratch;

  putStr("RAM: word/halfword/byte stores (WSTRB through the NoC)\n");
  scratch[0] = 0x11223344u;
  check("word store", scratch[0], 0x11223344u);
  bytes[1] = 0xAAu;
  check("byte store lane 1", scratch[0], 0x1122AA44u);
  halves[1] = 0xBEEFu;
  check("halfword store upper", scratch[0], 0xBEEFAA44u);
  check("byte load lane 3", bytes[3], 0xBEu);
}

static void testGpio(void)
{
  putStr("GPIO: direction, output set/clear and loopback input\n");
  GPIO_EN = PAD_LOOPBACK_MASK | (1u << PAD_TIMER1_CMP);
  GPIO_DIR = PAD_LOOPBACK_MASK | (1u << PAD_PASS) | (1u << PAD_DONE);
  check("DIR readback", GPIO_DIR, 0xC000FFFFu);

  GPIO_OUT = 0x0000A5A5u;
  check("OUT readback", GPIO_OUT, 0x0000A5A5u);
  check("IN loopback", GPIO_IN & PAD_LOOPBACK_MASK, 0x0000A5A5u);

  GPIO_OUT_SET = 0x00005A00u;
  check("OUT after SET", GPIO_OUT, 0x0000FFA5u);
  GPIO_OUT_CLR = 0x000000F0u;
  check("OUT after CLR", GPIO_OUT, 0x0000FF05u);
  check("IN loopback", GPIO_IN & PAD_LOOPBACK_MASK, 0x0000FF05u);
}

static void testTimer(void)
{
  uint32_t first;
  uint32_t second;

  putStr("TIMER: load, count and prescaler\n");
  TIMER_CTRL(0) = 0;
  TIMER_COUNT(0) = 0x00001234u;
  check("stopped COUNT holds", TIMER_COUNT(0), 0x00001234u);

  TIMER_CTRL(0) = TIMER_CTRL_ENABLE;
  check("CTRL readback", TIMER_CTRL(0), TIMER_CTRL_ENABLE);
  first = TIMER_COUNT(0);
  delay(4);
  second = TIMER_COUNT(0);
  check("COUNT advances", second > first, 1);

  TIMER_CTRL(0) = TIMER_CTRL_ENABLE | TIMER_CTRL_PRESCALER(7);
  first = TIMER_COUNT(0);
  delay(4);
  second = TIMER_COUNT(0);
  check("prescaled COUNT advances", second > first, 1);
  TIMER_CTRL(0) = 0;
}

static void testTimerToGpioInterrupt(void)
{
  uint32_t polls = 0;
  uint32_t status = 0;

  putStr("TIMER->GPIO: timer 1 compare pulse seen on GPIO pad 16\n");
  TIMER_CTRL(1) = 0;
  TIMER_CMP(1) = 100;
  GPIO_INT_TYPE_HI = GPIO_INT_TYPE_RISE << ((PAD_TIMER1_CMP - 16u) * 2u);
  GPIO_INT_EN = 1u << PAD_TIMER1_CMP;
  (void)GPIO_INT_STATUS;

  TIMER_CTRL(1) = TIMER_CTRL_ENABLE;
  while (((status & (1u << PAD_TIMER1_CMP)) == 0) && (polls < 1000)) {
    status = GPIO_INT_STATUS;
    polls++;
  }
  TIMER_CTRL(1) = 0;
  check("INTSTATUS pad 16", status & (1u << PAD_TIMER1_CMP),
        1u << PAD_TIMER1_CMP);

  (void)GPIO_INT_STATUS;
  check("INTSTATUS clear-on-read", GPIO_INT_STATUS, 0);
  GPIO_INT_EN = 0;
}

static void testUnmapped(void)
{
  putStr("NoC: read of an unmapped address completes (DECERR)\n");
  (void)REG32(UNMAPPED_ADDR);
  check("CPU still running", 1, 1);
}

int main(void)
{
  putStr("\nPicoRV32 booted over the networkOnChip mesh\n");
  testRam();
  testGpio();
  testTimer();
  testTimerToGpioInterrupt();
  testUnmapped();

  if (errors == 0) {
    putStr("ALL TESTS PASSED\n");
    GPIO_OUT_SET = (1u << PAD_DONE) | (1u << PAD_PASS);
  } else {
    putStr("TESTS FAILED: ");
    putHex(errors);
    putChar('\n');
    GPIO_OUT_SET = 1u << PAD_DONE;
  }
  return 0;
}
