#for BSVTools
ifndef AXIS_MK_INCLUDED
AXIS_MK_INCLUDED := 1

AXIS_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
EXTRA_BSV_LIBS += $(AXIS_ROOT)/src

$(info Adding AXI Stream library from $(AXIS_ROOT)/src)

endif
