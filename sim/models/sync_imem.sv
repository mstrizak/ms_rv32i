//-----------------------------------------------------------------------------
// sync_imem.sv
// Instruction-memory wrapper around sync_mem: adds the combinational
// flush-to-zero mux the core expects on instr_mem_flush_o (decodes as a
// full NOP through ctrl_decoder's opcode-0 default case).
//-----------------------------------------------------------------------------

module sync_imem #(
   parameter int ADDR_WIDTH = 12,
   parameter     INIT_FILE  = ""
)(
   input  logic         clk,
   input  logic         en_i,
   input  logic         flush_i,
   input  logic [31:0]  addr_i,
   output logic [31:0]  rdata_o
);

   logic [31:0] raw_s;

   sync_mem #(
      .ADDR_WIDTH (ADDR_WIDTH),
      .INIT_FILE  (INIT_FILE)
   ) mem_1 (
      .clk     (clk),
      .en_i    (en_i),
      .we_i    (4'b0000),
      .addr_i  (addr_i),
      .wdata_i (32'b0),
      .rdata_o (raw_s)
   );

   assign rdata_o = flush_i ? 32'h0 : raw_s;

endmodule : sync_imem
