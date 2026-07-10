###
# DO NOT CHANGE
###
TOP_MODULE=mkBlueJPEG
TESTBENCH_MODULE=mkTestbench
IGNORE_MODULES=mkTestbench mkTestsMainTest
MAIN_MODULE=BlueJPEG
TESTBENCH_FILE=test/Testbench.bsv
TEST_DIR=$(PWD)/test

# Initialize
-include .bsv_tools
ifndef BSV_TOOLS
$(error BSV_TOOLS is not set (Check .bsv_tools or specify it through the command line))
endif
VIVADO_ADD_PARAMS := ''
CONSTRAINT_FILES := ''
EXTRA_BSV_LIBS:=
EXTRA_LIBRARIES:=png X11 z pthread
RUN_FLAGS:=

PROJECT_NAME=BlueJPEG

ifeq ($(RUN_TEST),)
# RUN_TEST=TestsMainTest
# RUN_TEST=TestImageFunctions
# RUN_TEST=TestRGB2YCbCr
# RUN_TEST=TestAXIMM2S
# RUN_TEST=TestImageTiling
# RUN_TEST=TestBankedMemory
# RUN_TEST=TestTransposeBuffer
# RUN_TEST=TestDCT1D
# RUN_TEST=TestDCT2D
# RUN_TEST=TestQuantize
# RUN_TEST=TestZigZag
# RUN_TEST=TestMCUProc
# RUN_TEST=TestRLE
RUN_TEST=TestBlueJPEG
endif

# Default flags
EXTRA_FLAGS=-D "RUN_TEST=$(RUN_TEST)" -D "TESTNAME=mk$(RUN_TEST)"
EXTRA_FLAGS+=-show-schedule -D "BSV_TIMESCALE=1ns/1ps" -aggressive-conditions
# -keep-fires 

###
# User configuration
###

# Comment the following line if -O3 should be used during compilation
# Keep uncommented for short running simulations
CXX_NO_OPT := 1

# Any additional files added during compilation
# For instance for BDPI or Verilog/VHDL files for simulation
CPP_FILES += $(PWD)/src/BDPI/*.cpp

# Custom defines added to compile steps
EXTRA_FLAGS+=-I $(PWD)/src/BDPI -I $(PWD)/../../dep/BlueSY/src -Xc++ -std=c++23 -I $(PWD)/../../dep/CImg -Xc++ -std=c++23 -D cimg_use_png

# EXTRA_FLAGS+=-Wno-format-overflow -Wno-dangling-else

# Flags added to simulator execution
RUN_FLAGS+=#-V dump.vcd 
#-F -A

# Add additional parameters for IP-XACT generation. Passed directly to Vivado.
# Any valid TCL during packaging is allowed
# Typically used to fix automatic inference for e.g. clock assignments
# VIVADO_ADD_PARAMS += 'ipx::associate_bus_interfaces -busif M_AXI -clock sconfig_axi_aclk [ipx::current_core]'

# Add custom constraint files, Syntax: Filename,Load Order
# CONSTRAINT_FILES += "$(PWD)/constraints/custom.xdc,LATE"

VERILOG_SIM:=iverilog

# custom TCL flow
# PART=xcku3p-ffvb676-2-e
PART=xc7a35tcpg236-1
SCRIPT=$(CURDIR)/src/synth.tcl
CONSTRAINTS=$(CURDIR)/src/constr.tcl


# Do not change: Load libraries such as BlueAXI or BlueLib
ifneq ("$(wildcard $(PWD)/libraries/*/*.mk)", "")
include $(PWD)/libraries/*/*.mk
endif

# Do not change: Include base makefile
include $(BSV_TOOLS)/scripts/rules.mk
