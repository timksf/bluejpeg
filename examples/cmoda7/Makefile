
ENCODER_DIR := $(abspath ../../hdl/encoder)
REPO_ROOT := $(abspath ../..)
BLUEUART_DIR := $(REPO_ROOT)/dep/blueuart/hdl

BSV_TOOLS ?= $(REPO_ROOT)/dep/BSVTools
SIM ?= icarus
WAVES ?= 0
CMOD_UART_PRESCALER ?= 100
CMOD_UART_IDLE_TIMEOUT_CYCLES ?= 10000000
CMOD_SYNTH_SCRIPT ?= $(CURDIR)/synth.tcl

MAIN_MODULE := Encoder
TOP_MODULE := mkMiniJPEGEncoder
PROJECT_NAME := MiniJPEGEncoder
FULLHD_COLOR_MAIN_MODULE := CmodFullHDColorEncoder
FULLHD_COLOR_TOP_MODULE := mkCmodFullHDColorJPEGEncoder
FULLHD_COLOR_PROJECT_NAME := CmodFullHDColorJPEGEncoder
FULLHD_COLOR_SCRIPT := $(CURDIR)/synth_fullhd_color.tcl

SRCDIR := $(CURDIR)/lib
BUILDDIR := $(CURDIR)/build
CMOD_BSC_VERILOG_DIR := $(BUILDDIR)/verilog
ifneq ($(SIM_TYPE),VERILOG)
EXTRA_DIRS += $(CMOD_BSC_VERILOG_DIR)
endif
EXTRA_BSV_LIBS += $(ENCODER_DIR)/src $(BLUEUART_DIR)/src
EXTRA_FLAGS += -D "CMOD_UART_PRESCALER=$(CMOD_UART_PRESCALER)"
EXTRA_FLAGS += -D "CMOD_UART_IDLE_TIMEOUT_CYCLES=$(CMOD_UART_IDLE_TIMEOUT_CYCLES)"
VERILOGDIR_EXTRAS += $(CURDIR)/rtl
PART := xc7a35tcpg236-1
CONSTRAINTS := $(CURDIR)/cmoda7.xdc
SCRIPT := $(CMOD_SYNTH_SCRIPT)

include $(ENCODER_DIR)/Makefile

COCOTB_TB_DIR := $(CURDIR)/tb
COCOTB_BMP_PATH ?= $(REPO_ROOT)/assets/sample_192x192.bmp
COCOTB_OUTPUT_JPEG ?= $(BUILDDIR)/cmod_jpeg_core_cocotb.jpg
COCOTB_UART_PRESCALER ?= 4
COCOTB_UART_IDLE_TIMEOUT_CYCLES ?= 256
CMOD_BSC_VERILOG_FLAGS := $(filter-out -sim -verilog -vdir $(CMOD_BSC_VERILOG_DIR),$(COMPLETE_FLAGS)) -vdir $(CMOD_BSC_VERILOG_DIR)

.PHONY: compile_cmod_uart_bridges fullhd_color_bitstream

compile_top: compile_cmod_uart_bridges

fullhd_color_bitstream:
	$(MAKE) SIM_TYPE=VERILOG \
		MAIN_MODULE=$(FULLHD_COLOR_MAIN_MODULE) \
		TOP_MODULE=$(FULLHD_COLOR_TOP_MODULE) \
		PROJECT_NAME=$(FULLHD_COLOR_PROJECT_NAME) \
		CMOD_SYNTH_SCRIPT=$(FULLHD_COLOR_SCRIPT) \
		vivado_tcl

compile_cmod_uart_bridges: $(BUILDDIR)/bsc_defines | directories
	$(BSV) -elab -verilog $(CMOD_BSC_VERILOG_FLAGS) $(BSC_FLAGS) -g mkCmodUartAxisBridge -u $(SRCDIR)/CmodUartBridges.bsv
	$(BSV) -elab -verilog $(CMOD_BSC_VERILOG_FLAGS) $(BSC_FLAGS) -g mkCmodUartModeSwitch -u $(SRCDIR)/CmodUartBridges.bsv
	$(BSV) -elab -verilog $(CMOD_BSC_VERILOG_FLAGS) $(BSC_FLAGS) -g mkCmodAxis8ToAxis24Frame -u $(SRCDIR)/CmodUartBridges.bsv
	$(BSV) -elab -verilog $(CMOD_BSC_VERILOG_FLAGS) $(BSC_FLAGS) -g mkCmodUartAxiLiteMaster -u $(SRCDIR)/CmodUartBridges.bsv

.PHONY: cocotb cocotb-clean

cocotb:
	$(MAKE) SIM_TYPE=VERILOG CMOD_UART_PRESCALER=$(COCOTB_UART_PRESCALER) CMOD_UART_IDLE_TIMEOUT_CYCLES=$(COCOTB_UART_IDLE_TIMEOUT_CYCLES) compile_top
	$(MAKE) -C $(COCOTB_TB_DIR) \
		SIM="$(SIM)" \
		WAVES="$(WAVES)" \
		BMP_PATH="$(COCOTB_BMP_PATH)" \
		OUTPUT_JPEG="$(COCOTB_OUTPUT_JPEG)"

cocotb-clean:
	$(MAKE) -C $(COCOTB_TB_DIR) clean
