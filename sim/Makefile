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
	    tc_icache_hit_after_miss|tc_icache_lru_evict|tc_dcache_*) continue ;; \
	    tc_reset) extra="+MIDRESET_CYCLE=5 +CYCLES=60" ;; \
	    tc_stall_dmem_load) extra="+DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=3" ;; \
	    tc_stall_dmem_store) extra="+DMEM_STALL_CYCLE=4 +DMEM_STALL_LEN=3" ;; \
	    tc_stall_imem_fetch) extra="+IMEM_STALL_CYCLE=2 +IMEM_STALL_LEN=3" ;; \
	    tc_stall_plus_branch) extra="+DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=4" ;; \
	    tc_stall_plus_load_use) extra="+DMEM_STALL_CYCLE=3 +DMEM_STALL_LEN=5" ;; \
	    tc_stall_back_to_back) extra="+IMEM_STALL_CYCLE=1 +IMEM_STALL_LEN=2 +DMEM_STALL_CYCLE=5 +DMEM_STALL_LEN=3" ;; \
	    tc_icache_stall_plus_branch) extra="+IMEM_STALL_CYCLE=3 +IMEM_STALL_LEN=3" ;; \
	    *) extra="" ;; \
	  esac; \
	  echo "=== $$name ==="; \
	  out=$$(vvp $(SIM) +HEXFILE=progs/$$name.hex +EXPFILE=progs/$$name.expect +VCDFILE=work/$$name.vcd $$extra 2>&1); \
	  echo "$$out"; \
	  if ! echo "$$out" | grep -q "REGRESSION PASS"; then fail=1; fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== ALL TESTS PASSED ==="; else echo "=== SOME TESTS FAILED ==="; exit 1; fi

#-----------------------------------------------------------------------------
# core_top (cache-enabled) harness
#   make core-sim TEST=tc_arith_fwd
#   make core-wave TEST=tc_arith_fwd
#   make core-regress
#-----------------------------------------------------------------------------

SRC_CORE = $(RTL_DIR)/packages/util_pkg.sv \
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
           $(RTL_DIR)/icache.sv \
           $(RTL_DIR)/dcache.sv \
           $(RTL_DIR)/core_top.sv \
           models/sync_mem.sv \
           models/sync_imem.sv \
           tb/tb_core_top.sv

SIM_CORE = work/sim_core.vvp

.PHONY: core-sim core-wave core-regress

$(SIM_CORE): $(SRC_CORE)
	mkdir -p work
	iverilog -g2012 -o $(SIM_CORE) $(SRC_CORE)

core-sim: $(SIM_CORE)
	@if [ -z "$(TEST)" ]; then echo "Usage: make core-sim TEST=<name> [ARGS=...]"; exit 1; fi
	vvp $(SIM_CORE) +HEXFILE=progs/$(TEST).hex +EXPFILE=progs/$(TEST).expect +VCDFILE=work/$(TEST).vcd $(ARGS)

core-wave: core-sim
	gtkwave work/$(TEST).vcd &

# Only the 8 content-correctness tests are re-run here: the 6 tc_stall_* and
# tc_icache_stall_plus_branch tests are tied to TOP_RISCV's raw ready ports
# driven by the synthetic stall_injector, which core_top doesn't expose
# (its ready signals come from the real icache/dcache instead). Real-miss
# stall behavior is covered by the tc_icache_*/tc_dcache_* tests instead.
core-regress: $(SIM_CORE)
	@mkdir -p work
	@fail=0; \
	for name in tc_arith_fwd tc_branch_taken_beq tc_branch_not_taken tc_store_byte_enable \
	            tc_load_use_hazard tc_load_sign_extend tc_jal_jalr tc_reset \
	            tc_icache_hit_after_miss tc_icache_lru_evict \
	            tc_dcache_hit_after_miss tc_dcache_writeback tc_dcache_lru_evict; do \
	  test -f progs/$$name.hex || continue; \
	  case $$name in \
	    tc_reset) extra="+MIDRESET_CYCLE=15 +CYCLES=200" ;; \
	    *) extra="" ;; \
	  esac; \
	  echo "=== $$name ==="; \
	  out=$$(vvp $(SIM_CORE) +HEXFILE=progs/$$name.hex +EXPFILE=progs/$$name.expect +VCDFILE=work/$$name.vcd $$extra 2>&1); \
	  echo "$$out"; \
	  if ! echo "$$out" | grep -q "REGRESSION PASS"; then fail=1; fi; \
	done; \
	if [ $$fail -eq 0 ]; then echo "=== ALL CORE-TOP TESTS PASSED ==="; else echo "=== SOME CORE-TOP TESTS FAILED ==="; exit 1; fi

clean:
	rm -rf work
