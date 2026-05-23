
ENCODER_DIR := $(abspath ../../hdl/encoder)
REPO_ROOT := $(abspath ../..)

BSV_TOOLS ?= $(REPO_ROOT)/dep/BSVTools
SIM ?= icarus
WAVES ?= 0

MAIN_MODULE := Encoder
TOP_MODULE := mkMiniJPEGEncoder
PROJECT_NAME := MiniJPEGEncoder

SRCDIR := $(CURDIR)/lib
BUILDDIR := $(CURDIR)/build
EXTRA_BSV_LIBS += $(ENCODER_DIR)/src

include $(ENCODER_DIR)/Makefile

COCOTB_TB_DIR := $(CURDIR)/tb
COCOTB_BMP_PATH ?= $(REPO_ROOT)/assets/sample_192x192.bmp
COCOTB_OUTPUT_JPEG ?= $(BUILDDIR)/cmod_jpeg_core_cocotb.jpg

.PHONY: cocotb cocotb-clean

cocotb:
	$(MAKE) SIM_TYPE=VERILOG compile_top
	$(MAKE) -C $(COCOTB_TB_DIR) \
		SIM="$(SIM)" \
		WAVES="$(WAVES)" \
		BMP_PATH="$(COCOTB_BMP_PATH)" \
		OUTPUT_JPEG="$(COCOTB_OUTPUT_JPEG)"

cocotb-clean:
	$(MAKE) -C $(COCOTB_TB_DIR) clean