#-----------------------------------------------------------------------------
# sim/Makefile
# Icarus Verilog regression harness for TOP_RISCV.
#
#   make sim TEST=tc_arith_fwd        # run one test
#   make sim TEST=tc_arith_fwd ARGS="+TRACE"
#   make wave TEST=tc_arith_fwd       # run one test + open gtkwave
#   make regress                      # run every progs/tc_*.hex, summarize
#   make clean
#-----------------------------------------------------------------------------

RTL_DIR = ../src/design_sources_sv

SRC = $(RTL_DIR)/packages/util_pkg.sv \
      $(RTL_DIR)/control_path/ctrl_decoder.sv \
      $(RTL_DIR)/control_path/alu_decoder.sv \
      $(RTL_DIR)/control_path/forwarding_unit.sv \
      $(RTL_DIR)/control_path/hazard_unit.sv \
      $(RTL_DIR)/control_path/stall_unit.sv \
      $(RTL_DIR)/control_path/control_path.sv \
      $(RTL_DIR)/data_path/ALU.sv \
      $(RTL_DIR)/data_path/immediate.sv \
      $(RTL_DIR)/data_path/register_bank.sv \
      $(RTL_DIR)/data_path/data_path.sv \
      $(RTL_DIR)/TOP_RISCV.sv \
      models/sync_mem.sv \
      models/sync_imem.sv \
      models/stall_injector.sv \
      tb/tb_top_riscv.sv

SIM = work/sim.vvp

.PHONY: all sim wave regress clean

all: $(SIM)

$(SIM): $(SRC)
	mkdir -p work
	iverilog -g2012 -o $(SIM) $(SRC)

sim: $(SIM)
	@if [ -z "$(TEST)" ]; then echo "Usage: make sim TEST=<name> [ARGS=...]"; exit 1; fi
	vvp $(SIM) +HEXFILE=progs/$(TEST).hex +EXPFILE=progs/$(TEST).expect +VCDFILE=work/$(TEST).vcd $(ARGS)

wave: sim
	gtkwave work/$(TEST).vcd &

regress: $(SIM)
	@mkdir -p work
	@fail=0; \
	for t in progs/*.hex; do \
	  name=$$(basename $$t .hex); \
	  case $$name in \
	    tc_reset) extra="+MIDRESET_CYCLE=5 +CYCLES=60" ;; \
	    tc_stall_dmem_load) extra="+DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=3" ;; \
	    tc_stall_dmem_store) extra="+DMEM_STALL_CYCLE=4 +DMEM_STALL_LEN=3" ;; \
	    tc_stall_imem_fetch) extra="+IMEM_STALL_CYCLE=2 +IMEM_STALL_LEN=3" ;; \
	    tc_stall_plus_branch) extra="+DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=4" ;; \
	    tc_stall_plus_load_use) extra="+DMEM_STALL_CYCLE=3 +DMEM_STALL_LEN=5" ;; \
	    tc_stall_back_to_back) extra="+IMEM_STALL_CYCLE=1 +IMEM_STALL_LEN=2 +DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=3" ;; \
	    *) extra="" ;; \
	  esac; \
	  echo "=== $$name ==="; \
	  out=$$(vvp $(SIM) +HEXFILE=progs/$$name.hex +EXPFILE=progs/$$name.expect +VCDFILE=work/$$name.vcd $$extra 2>&1); \
	  echo "$$out"; \
	  if ! echo "$$out" | grep -q "REGRESSION PASS"; then fail=1; fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== ALL TESTS PASSED ==="; else echo "=== SOME TESTS FAILED ==="; exit 1; fi

clean:
	rm -rf work
