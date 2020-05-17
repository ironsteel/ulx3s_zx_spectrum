////////////////////////////////////////////////////////////////////////////////
//
// Filename: 	helloworld_tb.cpp
//
// Project:	Verilog Tutorial Example file
//
// Purpose:	To demonstrate a Verilog main() program that calls a local
//		serial port co-simulator.
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Written and distributed by Gisselquist Technology, LLC
//
// This program is hereby granted to the public domain.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.
//
////////////////////////////////////////////////////////////////////////////////
//
//
#include <verilatedos.h>
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <signal.h>
#include "verilated.h"
#include "Vsim.h"
#include "testb.h"
#include "vgasim.h"
#include <valarray>
#include <fstream>
#include <iostream>

#define SPI_CLK_RATIO 2
#define PS2_CLK_RATIO 7000

typedef std::vector<unsigned char> bytearray;
typedef std::ifstream bytestream;

using byte = std::uint8_t;

struct Regs
{
    union
    {
        std::uint16_t bc;

        struct
        {
            // The order of these bytes matters
            byte b;
            byte c;
        };
    };
};

class	TESTBENCH : public TESTB<Vsim> {
private:
	unsigned long	m_tx_busy_count;
	bool		m_done, m_test;
public:
	VGAWIN		m_vga;
private:

	void	init(void) {
		m_done = false;

		Glib::signal_idle().connect(sigc::mem_fun((*this),&TESTBENCH::on_tick));
                m_vga.signal_key_press_event().connect(sigc::mem_fun(*this, &TESTBENCH::onKeyPress), false);
	}
public:

	TESTBENCH(void) : m_test(false), m_vga(640, 480) {
		init();
	}

	TESTBENCH(int hres, int vres) : m_test(false), m_vga(hres, vres) {
		init();
	}

        bool onKeyPress(GdkEventKey* event)
        {
            int hw_code = event->hardware_keycode;
            if (hw_code == 36) {
                key_press(0x5a);
                delay_cycles(PS2_CLK_RATIO * 10);
                key_release(0x5a);
            }

            if (hw_code == 114) {
                key_press(0x29);
                delay_cycles(PS2_CLK_RATIO * 10);
                key_release(0x29);
            }
            std::cout << event->keyval << ' ' << event->hardware_keycode << ' ' << event->state << std::endl;

            return false;
        }

	void	trace(const char *vcd_trace_file_name) {
		fprintf(stderr, "Opening TRACE(%s)\n", vcd_trace_file_name);
		opentrace(vcd_trace_file_name);
	}

	void	close(void) {
		// TESTB<BASECLASS>::closetrace();
		m_done = true;
	}

	void	test_input(bool test_data) {
		m_test = test_data;
		//m_core->i_test = (m_test) ? 1:0;
	}

        void ps2_init() {
            cs_off();
            ps2_clk(1);
            ps2_data(1);
            delay_cycles(SPI_CLK_RATIO);
            delay_cycles(1);
        }

        unsigned int countSetBits(unsigned int n)
        {
            unsigned int count = 0;
            while (n) {
                count += n & 1;
                n >>= 1;
            }
            return count;
        }

        void ps2_xfer(uint8_t data) {
            int bitsSet = countSetBits(data);
            
            ps2_data(0x0);
            delay_cycles(PS2_CLK_RATIO);
            ps2_clk(0);
            delay_cycles(PS2_CLK_RATIO * 2);
            ps2_clk(1);
            delay_cycles(PS2_CLK_RATIO);
            for (int i = 0; i < 8; ++i) {
                ps2_data(((data >> i) & 0x01));
                delay_cycles(PS2_CLK_RATIO);
                ps2_clk(0);
                delay_cycles(PS2_CLK_RATIO * 2);
                ps2_clk(1);
                delay_cycles(PS2_CLK_RATIO);
            }

            printf("Parity %d\n", bitsSet);
            ps2_data(bitsSet % 2 == 0 ? 1 : 0);
            delay_cycles(PS2_CLK_RATIO);
            ps2_clk(0);
            delay_cycles(PS2_CLK_RATIO * 2);
            ps2_clk(1);


            delay_cycles(PS2_CLK_RATIO);
            ps2_data(1);
            delay_cycles(PS2_CLK_RATIO);
            ps2_clk(0);
            delay_cycles(PS2_CLK_RATIO*2);
            ps2_clk(1);

            delay_cycles(PS2_CLK_RATIO * 10);
        }

        void spi_init() {
            cs_off();
            spi_clk(1);
            spi_mosi(0x0);
            delay_cycles(SPI_CLK_RATIO);
            delay_cycles(1);
        }

        void cs_on() {
            spi_csn(0);
            delay_cycles(SPI_CLK_RATIO);
        }

        void cs_off() {
            spi_csn(1);
            delay_cycles(SPI_CLK_RATIO/2);
        }

        void spi_write(bytearray data) {
            for (int i = 0; i < data.size(); i++) {
                spi_write_byte(data[i]);
            }
        }

        void spi_write_repeat(int byte, int repeat) {
            for (int i = 0; i < repeat; ++i) {
                spi_write_byte(byte);
            }
        }
        void spi_write_byte(int byte) {
            for (int i = 7; i >=0; --i) {
                spi_clk(0);
                spi_mosi(((byte >> i) & 0x01));
                delay_cycles(SPI_CLK_RATIO/2);
                spi_clk(1);
                delay_cycles(SPI_CLK_RATIO/2);
            }
        }

        void write_start() {
            uint8_t data = 0x0;
            for (int i = 7; i >=0; --i) {
                spi_clk(0);
                spi_mosi(((data >> i) & 0x01));
                delay_cycles(SPI_CLK_RATIO/2);
                spi_clk(1);
                delay_cycles(SPI_CLK_RATIO/2);
            }
        }
        
        void ctrl_addr(uint32_t addr) {
            for (int i = 31; i >=0; --i) {
                spi_clk(0);
                spi_mosi(((addr >> i) & 0x01));
                delay_cycles(SPI_CLK_RATIO/2);
                spi_clk(1);
                delay_cycles(SPI_CLK_RATIO/2);
            }
        }

        void cpu_halt() {
            ctrl(2);
        }
        void cpu_continue() {
            ctrl(0);
        }
        void ctrl(int i) {
            cs_on();
            write_start();
            ctrl_addr(0xffffffff);
            spi_write_byte(i);
            cs_off();
        }

        void key_press(int i) {
            cs_on();
            write_start();
            ctrl_addr(0xf1ffffff);
            spi_write_byte(i);
            cs_off();
            delay_cycles(PS2_CLK_RATIO * 10);
            cs_on();
            write_start();
            ctrl_addr(0xf3ffffff);
            spi_write_byte(i);
            cs_off();
        }
        void key_release(int i) {
            cs_on();
            write_start();
            ctrl_addr(0xf2ffffff);
            spi_write_byte(i);
            cs_off();
            delay_cycles(PS2_CLK_RATIO * 10);
            cs_on();
            write_start();
            ctrl_addr(0xf4ffffff);
            spi_write_byte(i);
            cs_off();
        }
        void keyre(int i) {
            cs_on();
            write_start();
            ctrl_addr(0xf3ffffff);
            spi_write_byte(i);
            cs_off();
        }

        void slave_xfer_file(char *filename, uint32_t addr) {
            FILE *fp = fopen(filename, "rb");
            int byte;

            if (fp == NULL) {
                fprintf(stderr, "Cannot open file: %s %s", filename, strerror(errno));
            }
            cs_on();

            write_start();
            ctrl_addr(addr);

            while (!feof(fp)) {
                byte = fgetc(fp);
                spi_write_byte(byte);
            }

            cs_off();
            fclose(fp);
        }

        int read_bytes(bytestream& filedata, bytearray& out) {
            filedata.read(reinterpret_cast<char*>(&out[0]), out.size());
            return filedata.gcount();
        }

        void load_z80_compressed_stream(bytestream& filedata, int length=0xFFFF) {
            bytearray b=bytearray(1);
            bytearray escbyte=bytearray({0xED});
            int s=0;
            int repeat=0;
            int bytes_loaded=0;
            while (bytes_loaded < length) {
              if (read_bytes(filedata, b)) { 
                int nexts=s;
                if (s==0) {
                  if (b[0]==escbyte[0])
                    nexts=1;
                  else
                    spi_write(b);
                }
                if (s==1) {
                  if (b[0]==escbyte[0]) {
                    nexts=2;
                  } else {
                    spi_write(escbyte);
                    spi_write(b);
                    nexts=0;
                  }
                }
                if (s==2) {
                  repeat=b[0];
                  if (repeat==0) {
                    printf("end\n");
                    break;
                  }
                  nexts=3;
                }
                if (s==3) {
                  spi_write_repeat(b[0], repeat);
                  nexts=0;
                }
                s=nexts;
                bytes_loaded += 1;
              } else {
                break;
              }

            }
            printf("bytes loaded %d\n" ,bytes_loaded);
        }

          void  load_z80_v1_compressed_block(bytestream& filedata) {
            cs_on();
            spi_write(bytearray({0,0,0,0x40,0}));
            load_z80_compressed_stream(filedata);
            cs_off();
          }

          bool load_z80_v23_block(bytestream& filedata) {
            bytearray header = bytearray(3);
            Regs length;
            uint8_t page;
            uint32_t addr = -1;
            int compress = 0;
            if (read_bytes(filedata, header)) {
              length.b = header[0];
              length.c = header[1];
              page = header[2];
              printf("load z80 block: length=%d, page=%d\n", length.bc,page);
            } else {
              return false;
            }
            if (page==4)
              addr=0x8000;
            if (page==5)
              addr=0xC000;
            if (page==8)
              addr=0x4000;
            if (addr < 0) {
              printf("unsupported page ignored\n");
              //filedata.seek(length,1)
              return  true;
            }
            if (length.bc == 0xFFFF) {
              compress=0;
              length.bc = 0x4000;
            } else {
                compress=1;
            }
            printf("load z80 block: length=%d, page=%d, compress=%d\n" , length,page,compress);
            printf("addr=%04x compress=%d\n" , addr,compress);
            if (compress) {
              // Request load
              cs_on();
              spi_write(bytearray({0,(addr >> 24) & 0xFF, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF}));
              load_z80_compressed_stream(filedata, length.bc);
              cs_off();

            } else {
              printf("uncompressed v2/v3 may need FIXME\n");
              //self.load_stream(filedata,addr,16384)
            }
            return true;
        }

        void patch_rom(uint16_t pc, bytearray header) {
            printf("patch rom pc=%04x \n" , pc);
            // overwrite tape saving code in original ROM
            // with restore code and data from header
            uint16_t code_addr = 0x4C2;
            uint16_t header_addr = 0x500;
            cs_on();
            spi_write(bytearray({0, 0,0,0,0, 0xF3, 0xAF, 0x11, 0xFF, 0xFF, 0xC3, code_addr&0xFF, (code_addr>>8)&0xFF})); // overwrite start of ROM to JP 0x04C2
            cs_off();
            cs_on();
            spi_write(bytearray({0, 0,0,(code_addr>>8)&0xFF,code_addr&0xFF})); // overwrite 0x04C2
            // Z80 code that POPs REGs from header as stack data at 0x500
            // z80asm restore.z80asm; hexdump -v -e '/1 "0x%02X,"' a.bin
            // restores border color, registers I, AFBCDEHL' and AFBCDEHL
            spi_write(bytearray({0x31,(header_addr+9)&0xFF,((header_addr+9)>>8)&0xFF,0xF1,0xED,0x47,0xF1,0x1F,0xD3,0xFE,0xD1,0xD9,0xC1,0xD1,0xE1,0xD9,0xF1,0x08,0xFD,0xE1,0xDD,0xE1,0x21,0xE5,0xFF,0x39,0xF9,0xF1,0xC1,0xE1}));
            spi_write(bytearray({0x31})); // LD SP, ...
            spi_write_byte(header[8]);
            spi_write_byte(header[9]);
            spi_write_byte(header[10]);
            spi_write(bytearray({0xED})); // IM ...
            bytearray imarg = bytearray({0x46,0x56,0x5E,0x5E});
            spi_write(bytearray({imarg[header[29]&3]})); // IM mode
            if (header[27])
              spi_write(bytearray({0xFB})); // EI
            header[6]=pc&0xFF;
            header[7]=(pc>>8)&0xFF;
            spi_write(bytearray({0xC3})); // JP ...
            spi_write_byte(header[6]); // PC address of final JP
            spi_write_byte(header[7]); // PC address of final JP
            spi_write_byte(header[8]); // PC address of final JP
            cs_off();
            cs_on();
            spi_write(bytearray({0, 0,0,(header_addr>>8)&0xFF,header_addr&0xFF})); // overwrite 0x0500 with header
            // header fix: exchange A and F, A' and F' to become POPable
            uint8_t x=header[0];
            header[0]=header[1];
            header[1]=x;
            x=header[21];
            header[21]=header[22];
            header[22]=x;
            if (header[12]==255)
              header[12]=1;
            //header[12] ^= 7<<1 # FIXME border color
            spi_write(header); // AF and AF' now POPable
            cs_off();
        }

        void loadz80(const char *filename) {
            bytestream z(filename, std::ios::in | std::ios::binary);
            if (z.good()) {
                printf("GOOOOD\n");
            }
            bytearray header1 = bytearray(30);
            int read = read_bytes(z, header1);
            printf("read %d\n", read);
            Regs pc;
            pc.b = header1[6];
            pc.c = header1[7];    
            printf("%04x\n", header1[6]);
            printf("%04x\n", header1[7]);
            cpu_halt();
            slave_xfer_file("../roms/opense.rom", 0);
            if (pc.bc) {  // V1 format
              printf("Z80 v1\n");
              patch_rom(pc.bc, header1);
              if (header1[12] & 32)
                load_z80_v1_compressed_block(z);
              //else:
                //load_stream(z,0x4000)
            } else { // V2 or V3 format
              bytearray word = bytearray(2);
              read_bytes(z, word);
              Regs length2;
              length2.b = word[0];
              length2.c = word[1];
              printf("pc=%04x pc=%d\n" , length2.bc,length2.bc);
              if (length2.bc == 23)
                printf("Z80 v2\n");
              else {
                if (length2.bc == 54 || length2.bc == 55)
                  printf("Z80 v3\n");
                else {
                  printf("unsupported header2 length %d \n" ,length2.bc);
                  return;
                }
              }
              bytearray header2 = bytearray(length2.bc);
              read_bytes(z, header2);
              pc.b = header2[0];
              pc.c = header2[1];
              printf("pc=%04x pc=%d\n" , pc.bc,pc.bc);
              patch_rom(pc.bc, header1);
              while (load_z80_v23_block(z));
            }
            ctrl(3);
            ctrl(1);
            cpu_continue();
        }

	void	tick(void) {
		if (m_done)
			return;
		

		m_vga((m_core->VGA_VS)?1:0, (m_core->VGA_HS)?1:0,
			m_core->VGA_R,
			m_core->VGA_G,
			m_core->VGA_B);

		TESTB<Vsim>::tick();
	}

	bool	on_tick(void) {
		for(int i=0; i<5; i++)
			tick();
		return true;
	}
};


TESTBENCH	*tb;

int	main(int argc, char **argv) {
	Gtk::Main	main_instance(argc, argv);
	Verilated::commandArgs(argc, argv);

	tb = new TESTBENCH(640, 480);

        tb->opentrace("spectrum.vcd");

        tb->spi_init();
        tb->ps2_init();
        tb->loadz80("../snapshots/wow.z80");

        Gtk::Main::run(tb->m_vga);

	exit(0);
	printf("\n\nSimulation complete\n");
}
