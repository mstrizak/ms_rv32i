# RV32I — SystemVerilog conversion

Full SystemVerilog (IEEE 1800-2012) conversion of `RISCV_VHDL/RV32I/design_sources`.
The directory structure and module hierarchy mirror the original VHDL 1:1.

## Files / compile order

1. `packages/util_pkg.sv`            — alu_op_t, fwd_a_t, fwd_b_t enums + clogb2()
2. `control_path/ctrl_decoder.sv`    — opcode decoder
3. `control_path/alu_decoder.sv`     — ALU operation decoder
4. `control_path/forwarding_unit.sv` — EX-stage forwarding control
5. `control_path/hazard_unit.sv`     — load-use hazard stall
6. `control_path/control_path.sv`    — pipelined control path
7. `data_path/ALU.sv`                — parameterizable ALU
8. `data_path/immediate.sv`          — immediate extraction/extension
9. `data_path/register_bank.sv`      — 32x32 register file
10. `data_path/data_path.sv`         — 5-stage pipeline datapath
11. `TOP_RISCV.sv`                   — top level (structural)

Example (Icarus Verilog):
```
iverilog -g2012 packages/util_pkg.sv control_path/*.sv data_path/*.sv TOP_RISCV.sv -s TOP_RISCV
```

## Behavioral notes (faithfully preserved from the VHDL)

- **Reset is active-LOW and synchronous** (`reset == 1'b0` resets), gated by `ce`.
- **Register file writes on the FALLING clock edge** (`negedge clk`), so a value
  written in WB is readable in ID in the same cycle. x0 is hardwired to zero;
  reads are asynchronous.
- **The instruction memory is expected to be synchronous** (1-cycle read latency,
  acting as the IF/ID instruction register) and must honor `instr_mem_en_o`
  (stall) and `instr_mem_flush_o` (flush to NOP/zero). The data memory is also
  expected to have synchronous read (data arrives in the WB stage).
- VHDL enum ports (`alu_op_t`, `fwd_a_t`, `fwd_b_t`) became SystemVerilog
  `typedef enum` ports imported from `util_pkg`.
- The commented-out M-extension (mul/div/rem), zero/overflow flags, and eq_op
  code from the original is carried over as comments in the same places.
- The branch comparator in `data_path.sv` uses signed comparison for
  `branch_op == 2'b11` (BLTU/BGEU funct3 group), exactly as in the original
  VHDL — kept as-is for functional equivalence, though the RISC-V spec calls
  for an unsigned comparison there.

## Verification performed

Compiled cleanly with `iverilog -g2012` and passed smoke simulations:
arithmetic + EX/MEM/WB forwarding, taken-branch flush (BEQ), store byte-enable
decoding (SW), and load-use hazard stall (LW followed by dependent ADD).
