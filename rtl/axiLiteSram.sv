// Copyright (c) 2026 Tej Sanghavi.

// AXI4-Lite single-port SRAM holding the PicoRV32 boot image, stack and data.
//
// It is the RAM target on the SoC NoC: every instruction fetch, load and
// store from the CPU reaches it through niAxiLiteTarget. The NI drives AW and
// W in separate cycles, so each channel is captured independently and the
// write is committed once both have arrived. WSTRB is honoured with a
// read-modify-write of the addressed word, which is what lets the firmware
// use byte and halfword stores. Reads are registered (one cycle latency).
// Only one read and one write are tracked at a time; responses are always
// OKAY. The address is word-aligned; upper address bits outside DEPTH are
// ignored, the NoC address map already bounds the window.
//
// The memory is not reset. Simulation preloads it with $readmemh from the
// testbench.

`default_nettype none

module axiLiteSram
#(parameter int unsigned DEPTH = 4096
)
( input  var logic        i_clk
, input  var logic        i_arst_n

/* verilator lint_off UNUSEDSIGNAL */
, input  var logic [31:0] i_awaddr
/* verilator lint_on UNUSEDSIGNAL */
, input  var logic        i_awvalid
, output var logic        o_awready
, input  var logic [31:0] i_wdata
, input  var logic [3:0]  i_wstrb
, input  var logic        i_wvalid
, output var logic        o_wready
, output var logic [1:0]  o_bresp
, output var logic        o_bvalid
, input  var logic        i_bready

/* verilator lint_off UNUSEDSIGNAL */
, input  var logic [31:0] i_araddr
/* verilator lint_on UNUSEDSIGNAL */
, input  var logic        i_arvalid
, output var logic        o_arready
, output var logic [31:0] o_rdata
, output var logic [1:0]  o_rresp
, output var logic        o_rvalid
, input  var logic        i_rready
);

  localparam int unsigned WORD_ADDR_WIDTH = $clog2(DEPTH);

  // {{{ Write address channel
  // The word address is held until the write is committed; AWREADY is
  // withheld while an address is pending so a second one cannot overwrite it.

  logic awPending_q;
  logic awHandshake;
  logic writeCommit;

  always_comb
    o_awready = !awPending_q;

  always_comb
    awHandshake = i_awvalid && o_awready;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      awPending_q <= '0;
    else if (awHandshake || writeCommit)
      awPending_q <= awHandshake;
    else
      awPending_q <= awPending_q;

  logic [WORD_ADDR_WIDTH-1:0] writeAddr_q;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      writeAddr_q <= '0;
    else if (awHandshake)
      writeAddr_q <= i_awaddr[WORD_ADDR_WIDTH+1:2];
    else
      writeAddr_q <= writeAddr_q;

  // }}} Write address channel

  // {{{ Write data channel
  // Data and strobes are held until the write is committed, mirroring the
  // address channel.

  logic wPending_q;
  logic wHandshake;

  always_comb
    o_wready = !wPending_q;

  always_comb
    wHandshake = i_wvalid && o_wready;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      wPending_q <= '0;
    else if (wHandshake || writeCommit)
      wPending_q <= wHandshake;
    else
      wPending_q <= wPending_q;

  logic [31:0] writeData_q;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      writeData_q <= '0;
    else if (wHandshake)
      writeData_q <= i_wdata;
    else
      writeData_q <= writeData_q;

  logic [3:0] writeStrobe_q;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      writeStrobe_q <= '0;
    else if (wHandshake)
      writeStrobe_q <= i_wstrb;
    else
      writeStrobe_q <= writeStrobe_q;

  // }}} Write data channel

  // {{{ Write commit and response
  // The write is committed once address and data are both held and the
  // previous response has been accepted. BVALID is raised on commit and held
  // until BREADY.

  always_comb
    writeCommit = &{awPending_q
                  , wPending_q
                  , !o_bvalid
                  };

  logic bHandshake;

  always_comb
    bHandshake = o_bvalid && i_bready;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      o_bvalid <= '0;
    else if (writeCommit || bHandshake)
      o_bvalid <= writeCommit;
    else
      o_bvalid <= o_bvalid;

  always_comb
    o_bresp = '0;

  // }}} Write commit and response

  // {{{ Memory
  // Word-wide storage. Each byte lane takes the new byte when its strobe is
  // set, otherwise it keeps the stored byte, so the whole word can be
  // written back in one cycle.

  /* svlint off unpacked_array */
  logic [31:0] mem [DEPTH];
  /* svlint on unpacked_array */

  logic [3:0][7:0] writeWord;

  for (genvar i = 0; i < 4; i++) begin: perByteLane

    always_comb
      writeWord[i] = writeStrobe_q[i]
        ? writeData_q[i*8 +: 8]
        : mem[writeAddr_q][i*8 +: 8];

  end: perByteLane

  /* svlint off explicit_if_else */
  // Intended memory inference pattern.
  always_ff @(posedge i_clk)
    if (writeCommit)
      mem[writeAddr_q] <= writeWord;
  /* svlint on explicit_if_else */

  // }}} Memory

  // {{{ Read channel
  // A read is accepted whenever no read data is waiting. The addressed word
  // is registered and RVALID held until RREADY.

  logic arHandshake;
  logic rHandshake;

  always_comb
    o_arready = !o_rvalid;

  always_comb
    arHandshake = i_arvalid && o_arready;

  always_comb
    rHandshake = o_rvalid && i_rready;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      o_rvalid <= '0;
    else if (arHandshake || rHandshake)
      o_rvalid <= arHandshake;
    else
      o_rvalid <= o_rvalid;

  always_ff @(posedge i_clk, negedge i_arst_n)
    if (!i_arst_n)
      o_rdata <= '0;
    else if (arHandshake)
      o_rdata <= mem[i_araddr[WORD_ADDR_WIDTH+1:2]];
    else
      o_rdata <= o_rdata;

  always_comb
    o_rresp = '0;

  // }}} Read channel

endmodule

`resetall
