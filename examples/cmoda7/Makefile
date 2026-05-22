
ENCODER_DIR := $(abspath ../../hdl/encoder)
REPO_ROOT := $(abspath ../..)

BSV_TOOLS ?= $(REPO_ROOT)/dep/BSVTools

MAIN_MODULE := Encoder
TOP_MODULE := mkMiniJPEGEncoder
PROJECT_NAME := MiniJPEGEncoder

SRCDIR := $(CURDIR)/lib
BUILDDIR := $(CURDIR)/build
EXTRA_BSV_LIBS += $(ENCODER_DIR)/src

include $(ENCODER_DIR)/Makefile