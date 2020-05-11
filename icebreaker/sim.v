module sim(
  input  clock_12,

  output VGA_HS,
  output VGA_VS,
  output [3:0] VGA_R,
  output [3:0] VGA_G,
  output [3:0] VGA_B
);

  wire SPI_FLASH_CS;
  wire SPI_FLASH_MISO;
  wire SPI_FLASH_MOSI;
  wire SPI_FLASH_SCLK;

  spectrum spectrum_i(  
    .clock_12(clock_12),
    .flash_sck(SPI_FLASH_SCLK),
    .flash_csn(SPI_FLASH_CS),
    .flash_mosi(SPI_FLASH_MOSI),
    .flash_miso(SPI_FLASH_MISO),
    .VGA_VS(VGA_VS),
    .VGA_HS(VGA_HS),
    .VGA_R(VGA_R),
    .VGA_G(VGA_G),
    .VGA_B(VGA_B)
  );

  sim_spiflash #(
    .MEM_INIT_FILE("../roms/spectrum48.mem")
  ) spiflash (
    .SPI_FLASH_CS(SPI_FLASH_CS),
    .SPI_FLASH_MOSI(SPI_FLASH_MOSI),
    .SPI_FLASH_MISO(SPI_FLASH_MISO),
    .SPI_FLASH_SCLK(SPI_FLASH_SCLK)
  );

endmodule
