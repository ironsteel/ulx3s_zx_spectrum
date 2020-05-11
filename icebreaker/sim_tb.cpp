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
	}
public:

	TESTBENCH(void) : m_test(false), m_vga(640, 480) {
		init();
	}

	TESTBENCH(int hres, int vres) : m_test(false), m_vga(hres, vres) {
		init();
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

	void	tick(void) {
		if (m_done)
			return;

		/*
		// Measure how fast we are actually sending frames
		if ((m_tickcount & ((1<<28)-1))==0) {
			double	ticks_per_second = m_tickcount;
			time_t	seconds_passed = time(NULL)-m_start_time;
			if (seconds_passed != 0) {
			ticks_per_second /= (double)(time(NULL) - m_start_time);
			printf(" ********   %.6f TICKS PER SECOND\n", 
				ticks_per_second);
			}
		}
		*/

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
	//TESTB<Vspectrum>	*tb
	//	= new TESTB<Vspectrum>;

	tb = new TESTBENCH(640, 480);

        //tb->opentrace("spectrum.vcd");
	Gtk::Main::run(tb->m_vga);

	exit(0);
	printf("\n\nSimulation complete\n");
}
