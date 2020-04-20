`default_nettype none
module Spectrum (
  input         clk25_mhz,
  // Buttons
  input [6:0]   btn,
  // VGA
  output [3:0]  red,
  output [3:0]  green,
  output [3:0]  blue,
  output        hSync,
  output        vSync,
  // HDMI
  output [3:0]  gpdi_dp,
  output [3:0]  gpdi_dn,
  // Keyboard
  output        usb_fpga_pu_dp,
  output        usb_fpga_pu_dn,
  inout         ps2Clk,
  inout         ps2Data,
  // Leds
  output [7:0]  leds,
  output reg [15:0] diag
);

  wire          n_WR;
  wire          n_RD;
  wire [15:0]   cpuAddress;
  wire [7:0]    cpuDataOut;
  wire [7:0]    cpuDataIn;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_romCS;
  wire          n_ramCS;
  wire          n_ps2CS;

  reg [5:0]     cpuClkCount = 0;
  reg           cpuClock;

  reg           ram8kWritten = 0;

  // ===============================================================
  // System Clock generation
  // ===============================================================
  wire clk125, clk;

  pll pll_i (
    .clkin(clk25_mhz),
    .clkout0(clk125),
    .clkout1(clk)
  );

  // ===============================================================
  // Reset generation
  // ===============================================================
  reg [15:0] pwr_up_reset_counter = 0;
  wire       pwr_up_reset_n = &pwr_up_reset_counter;

  always @(posedge clk) begin
     if (!pwr_up_reset_n)
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
  end

  wire n_hard_reset = pwr_up_reset_n & btn[0];

  // ===============================================================
  // CPU
  // ===============================================================
  tv80n #(
    .Mode(1),
    .T2Write(1),
    .IOWait(0)
  ) cpu1 (
    .reset_n(n_hard_reset),
    .clk(cpuClock),
    .wait_n(1'b1),
    .int_n(1'b1),
    .nmi_n(1'b1),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .iorq_n(n_IORQ),
    .rd_n(n_RD),
    .wr_n(n_WR),
    .A(cpuAddress),
    .di(cpuDataIn),
    .do(cpuDataOut)
  );

  // ===============================================================
  // ROM 
  // ===============================================================
  wire [7:0] romOut;

  rom #(.MEM_INIT_FILE("../roms/spectrum48.mem"), .A_WIDTH(14)) rom16 (
    .clk(clk),
    .addr(cpuAddress[13:0]),
    .dout(romOut)
  );

  // ===============================================================
  // RAM
  // ===============================================================
  wire [7:0] ramOut;
  wire [7:0] vidOut;
  wire [12:0] vga_addr;
   
  dpram ram48 (
    .clk_a(cpuClock),
    .we_a(!n_ramCS & !n_memWR),
    .addr_a(cpuAddress - 16'h4000),
    .din_a(cpuDataOut),
    .dout_a(ramOut),
    .clk_b(clk_vga),
    .addr_b({3'b0, vga_addr}),
    .dout_b(vidOut)
  );

  // ===============================================================
  // Keyboard
  // ===============================================================
  wire [4:0]  key_data;
  wire [11:1] Fn;
  wire [2:0]  mod;
  wire [10:0] ps2_key;

    // Get PS/2 keyboard events
  ps2 ps2_kbd (
     .clk(clk),
     .ps2_clk(ps2Clk),
     .ps2_data(ps2Data),
     .ps2_key(ps2_key)
  );

  // Keyboard matrix
  keyboard the_keyboard (
    .reset(~n_hard_reset),
    .clk_sys(clk),
    .ps2_key(ps2_key),
    .addr(cpuAddress),
    .key_data(key_data),
    .Fn(Fn),
    .mod(mod)
  );

  // pull-ups for us2 connector 
  assign usb_fpga_pu_dp = 1;
  assign usb_fpga_pu_dn = 1;

  // ===============================================================
  // VGA
  // ===============================================================
  reg clk_vga = clk;
  reg clk_hdmi = clk125;
  wire vga_de;

  video vga (
    .clk(clk_vga),
    .vga_r(red),
    .vga_g(green),
    .vga_b(blue),
    .vga_de(vga_de),
    .vga_hs(hSync),
    .vga_vs(vSync),
    .vga_addr(vga_addr),
    .vga_data(vidOut)
  );

  // Convert VGA to HDMI
  HDMI_out vga2dvid (
    .pixclk(clk_vga),
    .pixclk_x5(clk_hdmi),
    .red({red, 4'b0}),
    .green({green, 4'b0}),
    .blue({blue, 4'b0}),
    .vde(vga_de),
    .hSync(hSync),
    .vSync(vSync),
    .gpdi_dp(gpdi_dp),
    .gpdi_dn(gpdi_dn)
  );

  // ===============================================================
  // MEMORY READ/WRITE LOGIC
  // ===============================================================

  assign n_ioWR = n_WR | n_IORQ;
  assign n_memWR = n_WR | n_MREQ;
  assign n_ioRD = n_RD | n_IORQ;
  assign n_memRD = n_RD | n_MREQ;

  // ===============================================================
  // Chip selects
  // ===============================================================

  assign n_ps2CS = cpuAddress[7:0] == 7'hfe && n_ioRD == 1'b0 ? 1'b0 : 1'b1;
  assign n_romCS = cpuAddress[15:14] != 0;
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_ps2CS == 1'b0 ? {3'b111, key_data} :
                      n_romCS == 1'b0 ? romOut :
                      n_ramCS == 1'b0 ? ramOut :
		                        8'hff;
 
  // ===============================================================
  // CPU clock generation
  // ===============================================================
  always @(posedge clk) begin
    if(cpuClkCount < 2) begin
      cpuClkCount <= cpuClkCount + 1;
    end else begin
      cpuClkCount <= 0;
    end
    if(cpuClkCount < 1) begin
      cpuClock <= 1'b0;
    end else begin
      cpuClock <= 1'b1;
    end
  end

  // ===============================================================
  // Leds
  // ===============================================================
  wire led1 = !n_ps2CS;
  wire led2 = !n_ramCS;
  wire led3 = n_WR;
  wire led4 = !n_hard_reset;

  assign leds = {4'b0, led4, led3, led2, led1};
  
  always @(posedge clk) begin
    diag <= {key_data, ps2_key};
  end
   
endmodule
