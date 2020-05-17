module sim(
  input  clock_12,

  output VGA_HS,
  output VGA_VS,
  output [3:0] VGA_R,
  output [3:0] VGA_G,
  output [3:0] VGA_B,

  input spi_clk,
  input spi_csn,
  input spi_mosi,

  input ps2clk,
  input ps2data
);

  wire spi_miso;

  spectrum spectrum_i(  
    .clock_12(clock_12),
    .ps2clk(ps2clk),
    .ps2data(ps2data),
    .slave_clk(spi_clk),
    .slave_cs_n(spi_csn),
    .slave_mosi(spi_mosi),
    .slave_miso(spi_miso),
    .VGA_VS(VGA_VS),
    .VGA_HS(VGA_HS),
    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B)
  );

endmodule
