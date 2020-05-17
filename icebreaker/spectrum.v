`default_nettype none
module spectrum
(
  input  clock_12,

  output VGA_CK,
  output VGA_DE,
  output VGA_HS,
  output VGA_VS,
  output [3:0] VGA_R,
  output [3:0] VGA_G,
  output [3:0] VGA_B,

  input  wire slave_mosi,
  output wire slave_miso,
  input  wire slave_cs_n,
  input  wire slave_clk,
`ifdef SIM
  input ps2clk,
  input ps2data,
`endif

  input btn,

  output LED0,
  output LED1
);

  wire          n_WR;
  wire          n_RD;
  wire          n_INT;
  wire [15:0]   cpuAddress;
  wire [7:0]    cpuDataOut;
  wire [7:0]    cpuDataIn;
  wire          n_memWR;
  wire          n_memRD;
  wire          n_ioWR;
  wire          n_ioRD;
  wire          n_MREQ;
  wire          n_IORQ;
  wire          n_M1;
  wire          n_romCS;
  wire          n_ramCS;
  wire          n_kbdCS;
  wire          n_joyCS;
  wire          n_video_ram_CS;
  
  reg [2:0]     border_color;
  wire          ula_we = ~cpuAddress[0] & ~n_IORQ & ~n_WR & n_M1;
  reg           old_ula_we;
  reg           sound;

  wire          cpuClock;
  wire          cpuClockEnable;

  assign VGA_CK = clk;

  // ===============================================================
  // System Clock generation
  // ===============================================================
  wire clk;

  wire clock_locked;
`ifndef SIM
  pll pll_i (
    .clock_in(clock_12),
    .clock_out(clk),
    .locked(clock_locked)
  );
`else
  assign clock_locked = !btn;
  assign clk = clock_12;
`endif

  assign cpuClock = clk;

  // ===============================================================
  // Reset generation
  // ===============================================================
  reg [15:0] pwr_up_reset_counter = 1;
  wire       pwr_up_reset_n = &pwr_up_reset_counter;

  always @(posedge clk) begin
     if (!pwr_up_reset_n)
       pwr_up_reset_counter <= pwr_up_reset_counter + 1;
  end

  // ===============================================================
  // CPU
  // ===============================================================
  wire [15:0] pc;
  
  reg [7:0] R_cpu_control = 0;
  wire loading = R_cpu_control[1];

  wire n_hard_reset = pwr_up_reset_n & ~R_cpu_control[0];

  wire irq;
  tv80n cpu1 (
    .reset_n(n_hard_reset),
    //.clk(cpuClock), // turbo mode 28MHz
    .clk(cpuClockEnable), // normal mode 3.5MHz
    .wait_n(~loading),
    .int_n(n_INT),
    .nmi_n(1'b1),
    .busrq_n(1'b1),
    .mreq_n(n_MREQ),
    .m1_n(n_M1),
    .iorq_n(n_IORQ),
    .wr_n(n_WR),
    .A(cpuAddress),
    .di(cpuDataIn),
    .dout(cpuDataOut),
    .rd_n(n_RD),
    .pc(pc)
  );

  wire [6:0] R_btn_joy;
  // TODO: add joystick support, for example an (S)NES controller
  //always @(posedge cpuClock)
  //  R_btn_joy <= btn | { usb_buttons[7],usb_buttons[6],usb_buttons[5],usb_buttons[4],usb_buttons[0],usb_buttons[1],1'b0};
  
  // ===============================================================
  // SPI Slave
  // ===============================================================
 
  wire spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire [7:0] spi_ram_di;
  wire [7:0] ramOut;
  wire [7:0] spi_ram_do = ramOut;

  wire irq;
  spi_ram_btn
  #(
    .c_sclk_capable_pin(1'b1),
    .c_addr_bits(32)
  )
  spi_ram_btn_inst
  (
    .clk(cpuClock),
    .csn(spi_slave_cs_n_i),
    .sclk(spi_slave_clk_i),
    .mosi(spi_slave_mosi_i),
    .miso(slave_miso),
    .btn(R_btn_joy),
    .irq(irq),
    .wr(spi_ram_wr),
    .rd(spi_ram_rd),
    .addr(spi_ram_addr),
    .data_in(spi_ram_do),
    .data_out(spi_ram_di)
  );
  
  wire spi_slave_clk_i;
	wire spi_slave_clk_r;
	wire spi_slave_clk_f;

	spi_simple_io_in spi_clk (
		.pad(slave_clk),
		.val(spi_slave_clk_i),
		.rise(spi_slave_clk_r),
		.fall(spi_slave_clk_f),
		.clk(clk),
		.rst(!clock_locked)
	);
  wire spi_slave_cs_n_i;
	wire spi_slave_csn_r;
	wire spi_slave_csn_f;

	spi_simple_io_in spi_cs (
		.pad(slave_cs_n),
		.val(spi_slave_cs_n_i),
		.rise(spi_slave_csn_r),
		.fall(spi_slave_csn_f),
		.clk(clk),
		.rst(!clock_locked)
	);

  wire spi_slave_mosi_i;
  wire spi_slave_mosi_r;
  wire spi_slave_mosi_f;

	spi_simple_io_in spi_mosi (
		.pad(slave_mosi),
		.val(spi_slave_mosi_i),
		.rise(spi_slave_mosi_r),
		.fall(spi_slave_mosi_f),
		.clk(clk),
		.rst(!clock_locked)
	);

  always @(posedge cpuClock) begin
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hFF) begin
      R_cpu_control <= spi_ram_di;
    end
  end
  

  // ===============================================================
  // Keyboard input via spi slave 
  // ===============================================================
  always @(posedge cpuClock) begin
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hF1) begin
      ps2_key <= {4'b100, spi_ram_di};
    end
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hF2) begin
      ps2_key <= {4'b110, spi_ram_di};
    end
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hF3) begin
      ps2_key <= {4'b000, spi_ram_di};
    end
    if (spi_ram_wr && spi_ram_addr[31:24] == 8'hF4) begin
      ps2_key <= {4'b010, spi_ram_di};
    end
  end

  // ===============================================================
  // Border color and sound
  // ===============================================================
  // TODO: Add sound
  always @(posedge cpuClock) begin
    old_ula_we <= ula_we;

    if (ula_we && !old_ula_we) begin
      border_color <= cpuDataOut[2:0];
      sound <= cpuDataOut[4];
    end
  end

  // ===============================================================
  // ROM
  // ===============================================================
  wire [7:0] romOut;
  up5k_zx_rom rom_i(
    .clk(clk),
    .wen(loading ? spi_ram_wr && spi_ram_addr[31:24] == 8'h00 && !n_romCS : 0),
    .addr(loading ? spi_ram_addr[13:0] : cpuAddress[13:0]),
    .wdata(spi_ram_di),
    .rdata(romOut)
  );

  // ===============================================================
  // RAM
  // ===============================================================
  wire [7:0] vidOut;
  wire [12:0] vga_addr;
  wire [7:0] attrOut;
  wire [12:0] attr_addr;

  wire [15:0] video_addr;
  wire [7:0] videoDataOut;

  video_ram 
  vram_i (
    .clk(clk),
    .we(loading ? spi_ram_wr && spi_ram_addr[31:24] == 8'h00 && !n_ramCS && !n_video_ram_CS : !n_ramCS & !n_memWR & !n_video_ram_CS),
    .addr_a(loading ? spi_ram_addr[12:0] : cpuAddress[12:0]),
    .din_a(loading ? spi_ram_di : cpuDataOut),
    .dout_a(videoDataOut),
    .addr_b(vga_addr),
    .dout_b(vidOut)
  );

  up5k_zx_ram
  ram48 (
    .clk_a(cpuClock),
    .we_a(loading ? spi_ram_wr && spi_ram_addr[31:24] == 8'h00 && !n_ramCS && n_video_ram_CS : !n_ramCS & !n_memWR & n_video_ram_CS),
    .addr_a(loading ?  spi_ram_addr[15:0] : cpuAddress[15:0]),
    .din_a(loading ? spi_ram_di : cpuDataOut),
    .dout_a(ramOut)
  );

  // ===============================================================
  // Keyboard
  // ===============================================================
  wire [4:0]  key_data;
  wire [11:1] Fn;
  wire [2:0]  mod;
  reg [10:0] ps2_key = 0;

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

  // ===============================================================
  // VGA
  // ===============================================================
  video vga (
    .clk(clk),
    .vga_r(VGA_R),
    .vga_g(VGA_G),
    .vga_b(VGA_B),
    .vga_de(VGA_DE),
    .vga_hs(VGA_HS),
    .vga_vs(VGA_VS),
    .vga_addr(vga_addr),
    .vga_data(vidOut),
    .n_int(n_INT),
    .border_color(border_color)
  );

  assign n_ioWR = n_WR | n_IORQ;
  assign n_memWR = n_WR | n_MREQ;
  assign n_ioRD = n_RD | n_IORQ;
  assign n_memRD = n_RD | n_MREQ;

  // ===============================================================
  // Chip selects
  // ===============================================================

  assign n_kbdCS = cpuAddress[7:0] == 8'HFE && n_ioRD == 1'b0 ? 1'b0 : 1'b1;
  assign n_joyCS = cpuAddress[7:0] == 8'd31 && n_ioRD == 1'b0 ? 1'b0 : 1'b1; // kempston joystick
  assign n_romCS = loading == 0 ? cpuAddress[15:14] != 0 : spi_ram_addr[15:14] != 0;
  assign n_video_ram_CS = loading == 0 ? ~(cpuAddress >= 16'h4000 && cpuAddress <= 16'h5AFF) : ~(spi_ram_addr[15:0] >= 16'h4000 && spi_ram_addr[15:0] <= 16'h5AFF);
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_kbdCS == 1'b0 ? {3'b111, key_data} :
                      n_joyCS == 1'b0 ? {2'b0, R_btn_joy[2], R_btn_joy[1], R_btn_joy[3], R_btn_joy[4], R_btn_joy[5], R_btn_joy[6]} : // x x (x or FIRE2 on modified hardware) FIRE1 UP DOWN LEFT RIGHT
                      n_romCS == 0 ? romOut :
                      n_video_ram_CS == 0 ? videoDataOut :
                      ramOut;

  // ===============================================================
  // CPU clock enable
  // ===============================================================
  // gives us ~3.5 Mhz with 60/40 duty cycle from 25.125 Mhz
  clock_div clock_div_i (
    .i_clk(clk),
    .i_rst(clock_locked),
    .i_clk_divider(4'd7),
    .o_clk(cpuClockEnable)
  );

  // ===============================================================
  // Leds
  // ===============================================================
  assign LED0 = R_cpu_control[0];
  assign LED1 = R_cpu_control[1];

endmodule

module spi_simple_io_in (
	input  wire pad,
	output wire val,
	output reg  rise,
	output reg  fall,
	input  wire clk,
	input  wire rst
);
`ifndef SIM
	// Signals
	wire iob_out;
	reg val_i;

	// IOB
	SB_IO #(
		.PIN_TYPE(6'b000000),
		.PULLUP(1'b0),
		.NEG_TRIGGER(1'b0),
		.IO_STANDARD("SB_LVCMOS")
	) cs_n_iob_I (
		.PACKAGE_PIN(pad),
		.CLOCK_ENABLE(1'b1),
		.INPUT_CLK(clk),
//		.OUTPUT_CLK(1'b0),
		.OUTPUT_ENABLE(1'b0),
		.D_OUT_0(1'b0),
		.D_OUT_1(1'b0),
		.D_IN_0(iob_out),
		.D_IN_1()
	);

	// Value and transition registers
	always @(posedge clk or posedge rst)
		if (rst) begin
			val_i <= 1'b0;
			rise  <= 1'b0;
			fall  <= 1'b0;
		end else begin
			val_i <=  iob_out;
			rise  <=  iob_out & ~val_i;
			fall  <= ~iob_out &  val_i;
		end

	assign val = val_i;
`else
  assign val = pad;
`endif

endmodule // spi_simple_io_in
