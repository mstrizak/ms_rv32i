//-----------------------------------------------------------------------------
// core_top.sv
// Cache-enabled core: TOP_RISCV + icache + dcache, each backed by its own
// memory. Self-contained (no external memory ports) so tests load program
// images via hierarchical $readmemh into the backing arrays, same pattern
// tb_top_riscv.sv already uses for the bare-core testbench.
//
// Named so a later (out-of-scope) multi-core phase can instantiate this
// module twice on a shared bus without further restructuring.
//-----------------------------------------------------------------------------

module core_top (
   input logic clk,
   input logic ce,
   input logic reset          // active-low, synchronous
);

   localparam int MEM_ADDR_WIDTH  = 12;   // 4096 words = 16KB data backing memory --
                                           // large enough for same-set (1KB-stride),
                                           // different-tag lines for dcache LRU testing
   localparam int IMEM_ADDR_WIDTH = 12;   // 4096 words = 16KB -- large enough to place
                                           // same-set (2KB-stride), different-tag lines
                                           // for icache LRU-eviction testing

   logic [31:0] instr_mem_address_s;
   logic [31:0] instr_mem_read_s;
   logic        instr_mem_flush_s;
   logic        instr_mem_ready_s;

   logic [31:0] data_mem_address_s;
   logic [31:0] data_mem_read_s;
   logic [31:0] data_mem_write_s;
   logic [3:0]  data_mem_we_s;
   logic        data_mem_en_s;
   logic        data_mem_ready_s;
   logic        instr_mem_en_s;

   TOP_RISCV core_1 (
      .clk                  (clk),
      .ce                   (ce),
      .reset                (reset),
      .instr_mem_address_o  (instr_mem_address_s),
      .instr_mem_read_i     (instr_mem_read_s),
      .instr_mem_flush_o    (instr_mem_flush_s),
      .instr_mem_en_o       (instr_mem_en_s),
      .instr_mem_ready_i    (instr_mem_ready_s),
      .data_mem_address_o   (data_mem_address_s),
      .data_mem_read_i      (data_mem_read_s),
      .data_mem_write_o     (data_mem_write_s),
      .data_mem_we_o        (data_mem_we_s),
      .data_mem_en_o        (data_mem_en_s),
      .data_mem_ready_i     (data_mem_ready_s)
   );

   // ---- Instruction side: icache + backing memory ----
   logic [31:0] imem_backing_address_s;
   logic        imem_backing_en_s;
   logic [31:0] imem_backing_read_s;

   icache icache_1 (
      .clk            (clk),
      .reset          (reset),
      .en_i           (instr_mem_en_s),
      .flush_i        (instr_mem_flush_s),
      .address_i      (instr_mem_address_s),
      .read_o         (instr_mem_read_s),
      .ready_o        (instr_mem_ready_s),
      .mem_address_o  (imem_backing_address_s),
      .mem_en_o       (imem_backing_en_s),
      .mem_read_i     (imem_backing_read_s)
   );

   sync_mem #(
      .ADDR_WIDTH (IMEM_ADDR_WIDTH)
   ) imem_backing_1 (
      .clk     (clk),
      .en_i    (imem_backing_en_s),
      .we_i    (4'b0000),
      .addr_i  (imem_backing_address_s),
      .wdata_i (32'b0),
      .rdata_o (imem_backing_read_s)
   );

   // ---- Data side: dcache + backing memory ----
   logic [31:0] dmem_backing_address_s;
   logic        dmem_backing_en_s;
   logic [3:0]  dmem_backing_we_s;
   logic [31:0] dmem_backing_write_s;
   logic [31:0] dmem_backing_read_s;

   dcache dcache_1 (
      .clk           (clk),
      .reset         (reset),
      .en_i          (data_mem_en_s),
      .we_i          (data_mem_we_s),
      .address_i     (data_mem_address_s),
      .write_i       (data_mem_write_s),
      .read_o        (data_mem_read_s),
      .ready_o       (data_mem_ready_s),
      .mem_address_o (dmem_backing_address_s),
      .mem_en_o      (dmem_backing_en_s),
      .mem_we_o      (dmem_backing_we_s),
      .mem_write_o   (dmem_backing_write_s),
      .mem_read_i    (dmem_backing_read_s)
   );

   sync_mem #(
      .ADDR_WIDTH (MEM_ADDR_WIDTH)
   ) dmem_backing_1 (
      .clk     (clk),
      .en_i    (dmem_backing_en_s),
      .we_i    (dmem_backing_we_s),
      .addr_i  (dmem_backing_address_s),
      .wdata_i (dmem_backing_write_s),
      .rdata_o (dmem_backing_read_s)
   );

endmodule : core_top
