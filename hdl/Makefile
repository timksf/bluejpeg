# BSVTools project for the BlueJPEG encoder and its PA200T test design.
#   make sim                                    Bluesim test, RUN_TEST selects test/<RUN_TEST>.bsv (default TestBlueJPEG)
#   make sim RUN_TEST=TestJpegSystem            pattern ROM -> encoder -> UART, checked against the C++ reference
#   make rom                                    regenerate rom/pattern_192x192.mem from assets/sample_192x192.bmp
#   make bitstream                              PA200T bitstream via BSVTools vivado_tcl (src/fpga/pa200t/script/synth.tcl)
#   make bitstream SYNTH=ooc TOP_MODULE=mkBlueJPEGTop_1920_12   out-of-context synthesis of a core variant (src/synth)

ifeq ($(SYNTH),ooc)
MAIN_MODULE      := synth/SynthTest
TOP_MODULE       ?= mkBlueJPEGTop_1920_12
PROJECT_NAME     := $(TOP_MODULE)_ooc
SCRIPT           := $(CURDIR)/src/synth/script/synth_ooc.tcl
endif

PROJECT_NAME     ?= BlueJPEG_PA200T
MAIN_MODULE      ?= fpga/pa200t/PA200T_JPEG
TOP_MODULE       ?= mkPA200T_JPEG_Top
TESTBENCH_MODULE := mkTestbench
TESTBENCH_FILE   := test/Testbench.bsv
IGNORE_MODULES   := mkTestbench mkTestsMainTest
TEST_DIR         := $(CURDIR)/test
RUN_TEST         ?= TestBlueJPEG
BSV_TOOLS        ?= $(abspath ../dep/BSVTools)
PART             := xc7a200tfbg484-2
SCRIPT           ?= $(CURDIR)/src/fpga/pa200t/script/synth.tcl

BUILDDIR ?= build/$(if $(filter VERILOG,$(SIM_TYPE)),$(PROJECT_NAME),$(RUN_TEST))

ASSETS_DIR := $(abspath ../assets)
ROM_DIR    := $(CURDIR)/rom
ROM_FILES  := $(wildcard $(ROM_DIR)/*.mem)

VIVADO_ADD_PARAMS :=
CONSTRAINT_FILES  :=
EXTRA_BSV_LIBS    := $(addprefix $(CURDIR)/src/,encoder system synth fpga/pa200t) $(TEST_DIR)/bdpi
EXTRA_LIBRARIES   := png X11 z pthread
RUN_FLAGS         :=

EXTRA_FLAGS := -D "RUN_TEST=$(RUN_TEST)" -D "TESTNAME=mk$(RUN_TEST)"
EXTRA_FLAGS += -show-schedule -D "BSV_TIMESCALE=1ns/1ps" -aggressive-conditions
EXTRA_FLAGS += -D ASSETS_DIR=\"$(ASSETS_DIR)\"

# Bluesim only: C++ reference models (test/bdpi) and image I/O
CXX_NO_OPT := 1
EXTRA_FLAGS += -I $(TEST_DIR)/bdpi -I $(abspath ../sw) -I $(abspath ../dep/BlueSY/src) -I $(abspath ../dep/CImg)
EXTRA_FLAGS += -Xc++ -std=c++23 -D cimg_use_png

# BlueLib has no include guard and is pulled in by BlueAXI.mk, so it is left out here
include $(filter-out $(CURDIR)/libraries/bluelib/%,$(wildcard $(CURDIR)/libraries/*/*.mk))

# BSC builds C objects next to their sources, so compile copies inside the build directory.
# This keeps the tree clean and lets several test builds run in parallel.
# BlueJ's JTAG socket model is only needed when simulating the JTAG path, which no test does.
C_FILES   :=
CSRC_DIR  := $(abspath $(BUILDDIR))/csrc
BDPI_SRCS := $(wildcard $(TEST_DIR)/bdpi/*.cpp)
CPP_FILES := $(addprefix $(CSRC_DIR)/,$(notdir $(BDPI_SRCS)))

$(shell mkdir -p $(BUILDDIR))
include $(BSV_TOOLS)/scripts/rules.mk

$(CSRC_DIR)/%.cpp: $(TEST_DIR)/bdpi/%.cpp
	@mkdir -p $(dir $@)
	@cp $< $@

# The simulator runs in the build directory and loads ROM images from there.
$(BUILDDIR)/%.mem: $(ROM_DIR)/%.mem
	@mkdir -p $(dir $@)
	@cp $< $@

$(BUILDDIR)/$(OUTFILE): $(CPP_FILES) $(addprefix $(BUILDDIR)/,$(notdir $(ROM_FILES)))

.PHONY: bitstream rom
bitstream:
	$(MAKE) --no-print-directory SIM_TYPE=VERILOG vivado_tcl

rom:
	$(MAKE) --no-print-directory sim RUN_TEST=TestGenPatternRom
	cp build/TestGenPatternRom/pattern_192x192.gen $(ROM_DIR)/pattern_192x192.mem
