// Copyright (c) 2026 Tej Sanghavi.

// tb_soc: boots the networkOnChip demo SoC and checks the firmware result.
//
// Board model: three free-running clocks with unrelated periods, resets held
// then released, GPIO pads 15:0 looped back out->in and pad 16 driven by the
// timer 1 compare interrupt. The RAM is preloaded from +firmware=<hex>.
//
// Monitors on the CPU's AXI4-Lite port (before the NoC):
// - stores to the console mailbox are printed as characters;
// - every timer/GPIO access and every unmapped access is logged with its
//   NoC response;
// - RAM traffic (instruction fetches, loads, stores) is counted, and logged
//   with +traceRam.
// The run ends when the firmware raises GPIO pad 31 (done); pad 30 is pass.

`default_nettype none

module tb_soc;

  localparam int unsigned CPU_HALF_PERIOD    = 4;
  localparam int unsigned FABRIC_HALF_PERIOD = 3;
  localparam int unsigned PERIPH_HALF_PERIOD = 7;
  localparam int unsigned RESET_TIME         = 100;
  localparam int unsigned TIMEOUT_CYCLES     = 3000000;

  localparam logic [31:0] CONSOLE_ADDR = 32'h0000_3FFC;
  localparam logic [31:0] RAM_END      = 32'h0000_3FFF;
  localparam logic [31:0] TIMER_BASE   = 32'h4000_0000;
  localparam logic [31:0] GPIO_BASE    = 32'h4000_1000;
  localparam logic [31:0] GPIO_END     = 32'h4000_1FFF;

  // {{{ Clocks and resets

  logic cpuClk;
  logic fabricClk;
  logic periphClk;
  logic arst_n;

  initial begin
    cpuClk = 1'b0;
    forever #(CPU_HALF_PERIOD) cpuClk = !cpuClk;
  end

  initial begin
    fabricClk = 1'b0;
    forever #(FABRIC_HALF_PERIOD) fabricClk = !fabricClk;
  end

  initial begin
    periphClk = 1'b0;
    forever #(PERIPH_HALF_PERIOD) periphClk = !periphClk;
  end

  initial begin
    arst_n = 1'b0;
    #(RESET_TIME + 1) arst_n = 1'b1;
  end

  // }}} Clocks and resets

  // {{{ DUT and board wiring

  logic        cpuTrap;
  logic [31:0] gpioIn;
/* verilator lint_off UNUSEDSIGNAL */
  logic [31:0] gpioOut;
  logic [31:0] gpioDir;
  logic        gpioInterrupt;
  logic [3:0]  timerIrq;
/* verilator lint_on UNUSEDSIGNAL */

  always_comb
    gpioIn = {15'd0, timerIrq[3], gpioOut[15:0]};

  socTop u_soc
  ( .i_cpuClk        (cpuClk)
  , .i_cpuArst_n     (arst_n)
  , .i_fabricClk     (fabricClk)
  , .i_fabricArst_n  (arst_n)
  , .i_periphClk     (periphClk)
  , .i_periphArst_n  (arst_n)
  , .o_cpuTrap       (cpuTrap)
  , .i_gpioIn        (gpioIn)
  , .o_gpioOut       (gpioOut)
  , .o_gpioDir       (gpioDir)
  , .o_gpioInterrupt (gpioInterrupt)
  , .o_timerIrq      (timerIrq)
  );

  // }}} DUT and board wiring

  // {{{ Firmware preload

  string firmwareFile;

  initial begin
    if (!$value$plusargs("firmware=%s", firmwareFile))
      firmwareFile = "build/firmware/firmware.hex";
    $display("[tb] loading %s into RAM", firmwareFile);
    $readmemh(firmwareFile, u_soc.u_ram.mem);
`ifdef TRACE
    $dumpfile("build/waves.fst");
    $dumpvars(0, tb_soc);
`endif
  end

  // }}} Firmware preload

  // {{{ CPU bus monitor

  bit          traceRam;
  int unsigned ramReads;
  int unsigned ramWrites;
  int unsigned peripheralAccesses;
  logic [31:0] readAddr;

  initial
    traceRam = $test$plusargs("traceRam");

  function automatic string targetName(logic [31:0] addr);
    if (addr <= RAM_END)
      return "RAM  ";
    else if ((addr >= TIMER_BASE) && (addr < GPIO_BASE))
      return "TIMER";
    else if ((addr >= GPIO_BASE) && (addr <= GPIO_END))
      return "GPIO ";
    else
      return "NONE ";
  endfunction

  function automatic string respName(logic [1:0] resp);
    case (resp)
      2'b00: return "OKAY";
      2'b01: return "EXOKAY";
      2'b10: return "SLVERR";
      default: return "DECERR";
    endcase
  endfunction

  always @(posedge cpuClk) begin
    if (u_soc.cpuAwvalid && u_soc.cpuAwready) begin
      if (u_soc.cpuAwaddr == CONSOLE_ADDR)
        $write("%c", u_soc.cpuWdata[7:0]);
      else if (u_soc.cpuAwaddr <= RAM_END) begin
        ramWrites <= ramWrites + 1;
        if (traceRam)
          $display("[bus] %0t WR RAM   0x%08h = 0x%08h strb %b", $time,
                   u_soc.cpuAwaddr, u_soc.cpuWdata, u_soc.cpuWstrb);
      end
      else begin
        peripheralAccesses <= peripheralAccesses + 1;
        $display("[bus] %0t WR %s 0x%08h = 0x%08h", $time,
                 targetName(u_soc.cpuAwaddr), u_soc.cpuAwaddr,
                 u_soc.cpuWdata);
      end
    end

    if (u_soc.cpuArvalid && u_soc.cpuArready)
      readAddr <= u_soc.cpuAraddr;

    if (u_soc.cpuRvalid && u_soc.cpuRready) begin
      if (readAddr <= RAM_END) begin
        ramReads <= ramReads + 1;
        if (traceRam)
          $display("[bus] %0t RD RAM   0x%08h = 0x%08h", $time, readAddr,
                   u_soc.cpuRdata);
      end
      else begin
        peripheralAccesses <= peripheralAccesses + 1;
        $display("[bus] %0t RD %s 0x%08h = 0x%08h %s", $time,
                 targetName(readAddr), readAddr, u_soc.cpuRdata,
                 respName(u_soc.cpuRresp));
      end
    end
  end

  // }}} CPU bus monitor

  // {{{ Result

  initial begin
    int unsigned cycles;

    $timeformat(-9, 0, " ns", 0);
    @(posedge arst_n);
    cycles = 0;
    while (!(gpioDir[31] && gpioOut[31]) && (cycles < TIMEOUT_CYCLES)) begin
      @(posedge cpuClk);
      cycles++;
      if (cpuTrap)
        $fatal(1, "[tb] FAIL: CPU trapped at %0t", $time);
    end

    if (cycles >= TIMEOUT_CYCLES)
      $fatal(1, "[tb] FAIL: timeout after %0d CPU cycles", cycles);
    $display("[tb] firmware done after %0d CPU cycles (%0t)", cycles, $time);
    $display("[tb]   CPU->RAM: %0d reads (fetch+load), %0d writes", ramReads,
             ramWrites);
    $display("[tb]   CPU->timer/GPIO: %0d accesses", peripheralAccesses);
    if (!gpioOut[30])
      $fatal(1, "[tb] FAIL: firmware reported errors");
    $display("[tb] PASS");
    $finish;
  end

  // }}} Result

endmodule

`resetall
