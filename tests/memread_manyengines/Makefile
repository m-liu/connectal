
CONNECTALDIR?=../..
INTERFACES = MemreadRequest MemreadIndication
BSVFILES = Memread.bsv Top.bsv
CPPFILES=testmemread.cpp
CONNECTALFLAGS += --bscflags " -D DataBusWidth=128"
CONNECTALFLAGS += -I$(CONNECTALDIR)/examples/memread

include $(CONNECTALDIR)/Makefile.connectal

