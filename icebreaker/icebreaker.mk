PIN_DEF ?= icebreaker.pcf

BUILDDIR = bin

compile: $(BUILDDIR)/toplevel.bit

prog: $(BUILDDIR)/toplevel.bit
	iceprog $^

testbench: $(VERILOG) $(VERILOG_SIM)
	iverilog -Wtimescale -DSIM=1 -o testbench $^ $(shell yosys-config --datdir/ice40/cells_sim.v)

tb: testbench
	vvp -N testbench -fst +vcd

$(BUILDDIR)/toplevel.json: $(VERILOG)
	mkdir -p $(BUILDDIR)
	yosys -p  "synth_ice40 -abc9 -json $@" $^

$(BUILDDIR)/toplevel.asc: $(PIN_DEF) $(BUILDDIR)/toplevel.json
	nextpnr-ice40 --up5k --timing-allow-fail --json $(filter-out $<,$^) --pcf $< --asc $@

$(BUILDDIR)/toplevel.bit: $(BUILDDIR)/toplevel.asc
	icepack -s $^ $@

.PHONY: sim
TOPMOD  := sim
VLOGFIL := $(TOPMOD).v
VCDFILE := $(TOPMOD).vcd
SIMPROG := $(TOPMOD)_tb
SIMFILE := $(SIMPROG).cpp
VDIRFB  := ./obj_dir

COSIMS  := vgasim.cpp image.cpp
sim: $(VCDFILE)

GCC := g++
CFLAGS = -g -Wall -std=c++17 -lpthread -I$(VINC) -I $(VDIRFB)
GFXFLAGS:= $(FLAGS) `pkg-config gtkmm-3.0 --cflags`
GFXLIBS := `pkg-config gtkmm-3.0 --libs`
CFLAGS  +=  $(GFXFLAGS)
#
# Modern versions of Verilator and C++ may require an -faligned-new flag
# CFLAGS = -g -Wall -faligned-new -I$(VINC) -I $(VDIRFB)

VERILATOR=verilator
VFLAGS := -O3 -MMD --trace -Wall -DSIM

## Find the directory containing the Verilog sources.  This is given from
## calling: "verilator -V" and finding the VERILATOR_ROOT output line from
## within it.  From this VERILATOR_ROOT value, we can find all the components
## we need here--in particular, the verilator include directory
VERILATOR_ROOT ?= $(shell bash -c '$(VERILATOR) -V|grep VERILATOR_ROOT | head -1 | sed -e "s/^.*=\s*//"')
##
## The directory containing the verilator includes
VINC := $(VERILATOR_ROOT)/include

$(VDIRFB)/V$(TOPMOD).cpp: $(VERILOG_SIM)
	$(VERILATOR) $(VFLAGS) --top-module $(TOPMOD) -cc $(VERILOG_SIM)

$(VDIRFB)/V$(TOPMOD)__ALL.a: $(VDIRFB)/V$(TOPMOD).cpp
	make --no-print-directory -C $(VDIRFB) -f V$(TOPMOD).mk

$(SIMPROG): $(SIMFILE) $(VDIRFB)/V$(TOPMOD)__ALL.a $(COSIMS)
	$(GCC) $(CFLAGS) $(VINC)/verilated.cpp				\
		$(VINC)/verilated_vcd_c.cpp $(SIMFILE) $(COSIMS)	\
		$(VDIRFB)/V$(TOPMOD)__ALL.a $(GFXLIBS) -o $(SIMPROG)

test: $(VCDFILE)

$(VCDFILE): $(SIMPROG)
	./$(SIMPROG)

clean:
	rm -rf ${BUILDDIR}

.SECONDARY:
.PHONY: compile clean prog
