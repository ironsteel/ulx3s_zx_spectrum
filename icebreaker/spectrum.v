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

  output flash_sck,
  output flash_csn,
  output flash_mosi,
  input flash_miso,

  input btn,

  output LED0
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

  reg [2:0]     cpuClockCount = 0;
  wire          cpuClock;
  wire          cpuClockEnable;

  assign VGA_CK = clk;

  assign LED0 = done;

  // ===============================================================
  // ROM loader
  // ===============================================================
  wire [13:0] loader_write_addr;
  wire [15:0] loader_write_data;
  wire loader_write;
  wire done;

  flash_loader flash_load_i (
    .clock(clk),
    .reset(!clock_locked),
    .reload(!btn),
    .index({4'b0000}),
    .loader_write_address(loader_write_addr),
    .loader_write_data(loader_write_data),
    .data_valid(loader_write),
    .done(done),

    //Flash load interface
    .flash_csn(flash_csn),
    .flash_sck(flash_sck),
    .flash_mosi(flash_mosi),
    .flash_miso(flash_miso)
   );

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
  //wire loading = R_cpu_control[1];
  wire loading = !done;

  wire n_hard_reset = pwr_up_reset_n & done;

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
  //always @(posedge cpuClock)
  //  R_btn_joy <= btn | { usb_buttons[7],usb_buttons[6],usb_buttons[5],usb_buttons[4],usb_buttons[0],usb_buttons[1],1'b0};

  // ===============================================================
  // SPI Slave
  // ===============================================================
 
  wire spi_ram_wr, spi_ram_rd;
  wire [31:0] spi_ram_addr;
  wire [7:0] spi_ram_di;
  wire [7:0] ramOut;
  wire [7:0] romOut;
  wire [7:0] spi_ram_do = ramOut;

  // ===============================================================
  // Border color and sound
  // ===============================================================

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
  up5k_zx_rom rom_i(
    .clk(clk),
    .wen(loader_write),
	  .addr(loading ? loader_write_addr : cpuAddress[13:0]),
	  .wdata(loader_write_data),
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
    .we(!n_ramCS & !n_memWR & !n_video_ram_CS),
    .addr_a(cpuAddress[12:0]),
    .din_a(cpuDataOut),
    .dout_a(videoDataOut),
    .addr_b(vga_addr),
    .dout_b(vidOut)
  );

  up5k_zx_ram
  ram48 (
    .clk_a(cpuClock),
    .we_a(!n_ramCS & !n_memWR & n_video_ram_CS),
    .addr_a(cpuAddress),
    .din_a(cpuDataOut),
    .dout_a(ramOut)
  );

  // ===============================================================
  // Keyboard
  // ===============================================================
  wire [4:0]  key_data;
  wire [11:1] Fn;
  wire [2:0]  mod;
  wire [10:0] ps2_key;

  // Get PS/2 keyboard events
  /*ps2 ps2_kbd (
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
  );*/

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
  assign n_romCS = cpuAddress[15:14] != 0;
  assign n_video_ram_CS = ~(cpuAddress >= 16'h4000 && cpuAddress <= 16'h5AFF);
  assign n_ramCS = !n_romCS;

  // ===============================================================
  // Memory decoding
  // ===============================================================

  assign cpuDataIn =  n_kbdCS == 1'b0 ? {3'b111, key_data} :
                      n_joyCS == 1'b0 ? {2'b0, R_btn_joy[2], R_btn_joy[1], R_btn_joy[3], R_btn_joy[4], R_btn_joy[5], R_btn_joy[6]} : // x x (x or FIRE2 on modified hardware) FIRE1 UP DOWN LEFT RIGHT
                      n_romCS == 0 ? romOut : 
                      n_video_ram_CS == 0 ? videoDataOut : ramOut;

  // ===============================================================
  // CPU clock enable
  // ===============================================================
   
  always @(posedge cpuClock) begin
      cpuClockCount <= cpuClockCount + 1;
  end

  assign cpuClockEnable = cpuClockCount[2]; // 3.5Mhz

  // ===============================================================
  // Leds
  // ===============================================================
  assign LED0 = done;

endmodule
