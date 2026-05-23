TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ns

EXAMPLE_DIR := $(abspath ..)
BUILD_DIR := $(EXAMPLE_DIR)/build
RTL_DIR := $(EXAMPLE_DIR)/rtl
REPO_ROOT := $(abspath ../../..)
BSC_VERILOG_DIR := $(REPO_ROOT)/hdl/encoder/build/BlueJPEG/src

DUT = cmod_jpeg_core
COCOTB_TEST_MODULES = test_cmod_jpeg_core
COCOTB_TOPLEVEL = $(DUT)
MODULE = $(COCOTB_TEST_MODULES)
TOPLEVEL = $(COCOTB_TOPLEVEL)

VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v
VERILOG_SOURCES += $(BUILD_DIR)/verilog/mkMiniJPEGEncoder.v
VERILOG_SOURCES += $(wildcard $(BSC_VERILOG_DIR)/*.v)

export BMP_PATH ?= $(abspath ../../../assets/sample_192x192.bmp)
export OUTPUT_JPEG ?= $(BUILD_DIR)/cmod_jpeg_core_cocotb.jpg
export EXPECTED_WIDTH ?= 192
export EXPECTED_HEIGHT ?= 192

COMPILE_ARGS += -g2012

ifeq ($(SIM), icarus)
	COCOTB_PLUSARGS += -fst
else ifeq ($(SIM), verilator)
	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
		VERILATOR_TRACE = 1
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim