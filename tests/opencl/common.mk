ROOT_DIR := $(realpath ../../..)

TARGET ?= opaesim

XRT_SYN_DIR ?= $(VORTEX_HOME)/hw/syn/xilinx/xrt
XRT_DEVICE_INDEX ?= 0

ifeq ($(XLEN),64)
VX_CFLAGS += -march=rv64imafd -mabi=lp64d
K_CFLAGS += -march=rv64imafd -mabi=ilp64d
STARTUP_ADDR ?= 0x180000000
else
VX_CFLAGS += -march=rv32imaf -mabi=ilp32f
K_CFLAGS += -march=rv32imaf -mabi=ilp32f
STARTUP_ADDR ?= 0x80000000
endif

POCL_CC_PATH ?= $(TOOLDIR)/pocl/compiler
POCL_RT_PATH ?= $(TOOLDIR)/pocl/runtime

LLVM_POCL ?= $(TOOLDIR)/llvm-vortex

K_CFLAGS  += -v -O3 --sysroot=$(RISCV_SYSROOT) --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH) -Xclang -target-feature -Xclang +vortex
K_CFLAGS  += -fno-rtti -fno-exceptions -nostartfiles -fdata-sections -ffunction-sections
K_CFLAGS  += -I$(VORTEX_KN_PATH)/include -DNDEBUG
K_LDFLAGS += -Wl,-Bstatic,--gc-sections,-T$(VORTEX_KN_PATH)/linker/vx_link$(XLEN).ld,--defsym=STARTUP_ADDR=$(STARTUP_ADDR) $(ROOT_DIR)/kernel/libvortexrt.a -lm

CXXFLAGS += -std=c++11 -Wall -Wextra -Wfatal-errors
CXXFLAGS += -Wno-deprecated-declarations -Wno-unused-parameter -Wno-narrowing
CXXFLAGS += -pthread
CXXFLAGS += -I$(POCL_RT_PATH)/include

# Debugigng
ifdef DEBUG
	CXXFLAGS += -g -O0
else    
	CXXFLAGS += -O2 -DNDEBUG
endif

ifeq ($(TARGET), fpga)
	OPAE_DRV_PATHS ?= libopae-c.so
else
ifeq ($(TARGET), asesim)
	OPAE_DRV_PATHS ?= libopae-c-ase.so
else
ifeq ($(TARGET), opaesim)
	OPAE_DRV_PATHS ?= libopae-c-sim.so
endif	
endif
endif

OBJS := $(addsuffix .o, $(filter-out main.cc,$(notdir $(SRCS))))

all: $(PROJECT) kernel.pocl
 
kernel.pocl: $(SRC_DIR)/kernel.cl
	LD_LIBRARY_PATH=$(LLVM_POCL)/lib:$(POCL_CC_PATH)/lib:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) LLVM_PREFIX=$(LLVM_VORTEX) POCL_DEBUG=all POCL_VORTEX_CFLAGS="$(K_CFLAGS)" POCL_VORTEX_LDFLAGS="$(K_LDFLAGS)" $(POCL_CC_PATH)/bin/poclcc -o kernel.pocl $^
 
%.cc.o: $(SRC_DIR)/%.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.cpp.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.c.o: $(SRC_DIR)/%.c
	$(CC) $(CXXFLAGS) -c $< -o $@

main.cc.o: $(SRC_DIR)/main.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

main.cc.host.o: $(SRC_DIR)/main.cc
	$(CXX) $(CXXFLAGS) -DHOSTGPU -c $< -o $@

$(PROJECT): main.cc.o $(OBJS) 
	$(CXX) $(CXXFLAGS) $^ $(LDFLAGS) -L$(ROOT_DIR)/runtime/stub -lvortex -L$(POCL_RT_PATH)/lib -lOpenCL -o $@

$(PROJECT).host: main.cc.host.o $(OBJS)
	$(CXX) $(CXXFLAGS) $^ $(LDFLAGS) -lOpenCL -o $@

run-gpu: $(PROJECT).host kernel.pocl
	./$(PROJECT).host $(OPTS)

run-simx: $(PROJECT) kernel.pocl   
	LD_LIBRARY_PATH=$(POCL_RT_PATH)/lib:$(ROOT_DIR)/runtime/simx:$(LD_LIBRARY_PATH) ./$(PROJECT) $(OPTS)

run-rtlsim: $(PROJECT) kernel.pocl   
	LD_LIBRARY_PATH=$(POCL_RT_PATH)/lib:$(ROOT_DIR)/runtime/rtlsim:$(LD_LIBRARY_PATH) ./$(PROJECT) $(OPTS)

run-opae: $(PROJECT) kernel.pocl
	SCOPE_JSON_PATH=$(ROOT_DIR)/runtime/opae/scope.json OPAE_DRV_PATHS=$(OPAE_DRV_PATHS) LD_LIBRARY_PATH=$(POCL_RT_PATH)/lib:$(ROOT_DIR)/runtime/opae:$(LD_LIBRARY_PATH) ./$(PROJECT) $(OPTS)

run-xrt: $(PROJECT) kernel.pocl
ifeq ($(TARGET), hw)
	XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_RT_PATH)/lib:$(ROOT_DIR)/runtime/xrt:$(LD_LIBRARY_PATH) ./$(PROJECT) $(OPTS)
else
	XCL_EMULATION_MODE=$(TARGET) XRT_INI_PATH=$(XRT_SYN_DIR)/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_RT_PATH)/lib:$(ROOT_DIR)/runtime/xrt:$(LD_LIBRARY_PATH) ./$(PROJECT) $(OPTS)
endif

.depend: $(SRCS)
	$(CXX) $(CXXFLAGS) -MM $^ > .depend;

clean:
	rm -rf $(PROJECT) $(PROJECT).host *.o .depend

clean-all: clean
	rm -rf *.dump *.pocl

ifneq ($(MAKECMDGOALS),clean)
    -include .depend
endif
