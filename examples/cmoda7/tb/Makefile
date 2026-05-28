TOPLEVEL_LANG = verilog

SIM ?= icarus
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

EXAMPLE_DIR := $(abspath ..)
BUILD_DIR := $(EXAMPLE_DIR)/build
RTL_DIR := $(EXAMPLE_DIR)/rtl
REPO_ROOT := $(abspath ../../..)
BSC_VERILOG_DIR := $(REPO_ROOT)/hdl/encoder/build/BlueJPEG/src
VIVADO ?= $(shell which vivado)
XILINX_VERILOG_SRC ?= $(abspath $(dir $(VIVADO))/../../data/verilog/src)
XILINX_UNISIMS_DIR ?= $(XILINX_VERILOG_SRC)/unisims
XILINX_GLBL ?= $(XILINX_VERILOG_SRC)/glbl.v
TOP_UART_BAUD_RATE ?= 25000000
TOP_UART_BIT_CYCLES ?= 4

DUT ?= cmod_jpeg_core
COCOTB_TEST_MODULES ?= test_cmod_jpeg_core
COCOTB_TOPLEVEL ?= $(DUT)
MODULE = $(COCOTB_TEST_MODULES)
TOPLEVEL = $(COCOTB_TOPLEVEL)
SIM_BUILD ?= sim_build/$(DUT)

UART_RTL_SOURCES = \
	$(RTL_DIR)/uart_rx.v \
	$(RTL_DIR)/uart_tx.v \
	$(RTL_DIR)/uart_axis_rx.v \
	$(RTL_DIR)/axis_uart_tx.v \
	$(RTL_DIR)/uart_axis_bridge.v

ifeq ($(DUT),cmod_jpeg_core)
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v
VERILOG_SOURCES += $(BUILD_DIR)/verilog/mkMiniJPEGEncoder.v
VERILOG_SOURCES += $(wildcard $(BSC_VERILOG_DIR)/*.v)
else ifeq ($(DUT),uart_axis_bridge)
VERILOG_SOURCES += $(UART_RTL_SOURCES)
else ifeq ($(DUT),cmod_jpeg_top)
VERILOG_SOURCES += $(RTL_DIR)/cmod_jpeg_top.v
VERILOG_SOURCES += $(RTL_DIR)/cmod_jpeg_core.v
VERILOG_SOURCES += $(UART_RTL_SOURCES)
VERILOG_SOURCES += $(BUILD_DIR)/verilog/mkMiniJPEGEncoder.v
VERILOG_SOURCES += $(wildcard $(BSC_VERILOG_DIR)/*.v)
VERILOG_SOURCES += $(XILINX_GLBL)
COMPILE_ARGS += -P cmod_jpeg_top.UART_BAUD_RATE=$(TOP_UART_BAUD_RATE)
endif

export BMP_PATH ?= $(abspath ../../../assets/sample_192x192.bmp)
export OUTPUT_JPEG ?= $(BUILD_DIR)/cmod_jpeg_core_cocotb.jpg
export TOP_OUTPUT_JPEG ?= $(BUILD_DIR)/cmod_jpeg_top_uart_cocotb.jpg
export EXPECTED_WIDTH ?= 192
export EXPECTED_HEIGHT ?= 192
export UART_BIT_CYCLES ?= 100

COMPILE_ARGS += -g2012

ifeq ($(SIM), icarus)
	COCOTB_PLUSARGS += -fst
	ifeq ($(DUT),cmod_jpeg_top)
		COMPILE_ARGS += -y $(XILINX_UNISIMS_DIR) -s glbl
	endif
else ifeq ($(SIM), verilator)
	ifeq ($(WAVES), 1)
		COMPILE_ARGS += --trace-fst
		VERILATOR_TRACE = 1
	endif
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

.PHONY: uart-axis
uart-axis:
	$(MAKE) DUT=uart_axis_bridge COCOTB_TEST_MODULES=test_uart_axis_bridge SIM_BUILD=sim_build/uart_axis_bridge

.PHONY: top-uart
top-uart:
	$(MAKE) DUT=cmod_jpeg_top COCOTB_TEST_MODULES=test_cmod_jpeg_top SIM_BUILD=sim_build/cmod_jpeg_top UART_BIT_CYCLES=$(TOP_UART_BIT_CYCLES)
