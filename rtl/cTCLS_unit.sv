// Copyright 2021 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// configurable Tripli-Core Lock-Step unit

module cTCLS_unit #(
  parameter int unsigned InstrRdataWidth,
  parameter int unsigned NExtPerfCounters,
  parameter int unsigned DataWidth,
  parameter int unsigned BEWidth
) (
  input  logic                             clk_i,
  input  logic                             rst_ni,

  XBAR_PERIPH_BUS.Slave                    speriph_slave,



  // Ports to connect Interconnect/rest of system
  input  logic [2:0][                 3:0] intc_core_id_i,
  input  logic [2:0][                 5:0] intc_cluster_id_i,

  input  logic [2:0]                       intc_clock_en_i,
  input  logic [2:0]                       intc_fetch_en_i,
  input  logic [2:0]                       intc_fregfile_disable_i,
  input  logic [2:0][                31:0] intc_boot_addr_i,
  output logic [2:0]                       intc_core_busy_o,

  input  logic [2:0]                       intc_irq_req_i,
  output logic [2:0]                       intc_irq_ack_o,
  input  logic [2:0][                 4:0] intc_irq_id_i,
  output logic [2:0][                 4:0] intc_irq_ack_id_o,

  output logic [2:0]                       intc_instr_req_o,
  input  logic [2:0]                       intc_instr_gnt_i,
  output logic [2:0][                31:0] intc_instr_addr_o,
  input  logic [2:0][ InstrRdataWidth-1:0] intc_instr_r_rdata_i,
  input  logic [2:0]                       intc_instr_r_valid_i,

  input  logic [2:0]                       intc_debug_req_i,

  output logic [2:0]                       intc_core_bus_req_o,
  output logic [2:0][                31:0] intc_core_bus_add_o,
  output logic [2:0]                       intc_core_bus_wen_o,
  output logic [2:0][       DataWidth-1:0] intc_core_bus_wdata_o,
  output logic [2:0][         BEWidth-1:0] intc_core_bus_be_o,
  input  logic [2:0]                       intc_core_bus_gnt_i,
  input  logic [2:0]                       intc_core_bus_r_opc_i,
  input  logic [2:0][       DataWidth-1:0] intc_core_bus_r_rdata_i,
  input  logic [2:0]                       intc_core_bus_r_valid_i,

  input  logic [2:0][NExtPerfCounters-1:0] intc_perf_counters_i,

  // Ports to connect Cores
  output logic [2:0]                       core_rst_no,

  output logic [2:0][                 3:0] core_core_id_o,
  output logic [2:0][                 5:0] core_cluster_id_o,

  output logic [2:0]                       core_clock_en_o,
  output logic [2:0]                       core_fetch_en_o,
  output logic [2:0]                       core_fregfile_disable_o,
  output logic [2:0][                31:0] core_boot_addr_o,
  input  logic [2:0]                       core_core_busy_i,

  output logic [2:0]                       core_irq_req_o,
  input  logic [2:0]                       core_irq_ack_i,
  output logic [2:0][                 4:0] core_irq_id_o,
  input  logic [2:0][                 4:0] core_irq_ack_id_i,

  input  logic [2:0]                       core_instr_req_i,
  output logic [2:0]                       core_instr_gnt_o,
  input  logic [2:0][                31:0] core_instr_addr_i,
  output logic [2:0][ InstrRdataWidth-1:0] core_instr_r_rdata_o,
  output logic [2:0]                       core_instr_r_valid_o,

  output logic [2:0]                       core_debug_req_o,

  input  logic [2:0]                       core_core_bus_req_i,
  input  logic [2:0][                31:0] core_core_bus_add_i,
  input  logic [2:0]                       core_core_bus_wen_i,
  input  logic [2:0][       DataWidth-1:0] core_core_bus_wdata_i,
  input  logic [2:0][         BEWidth-1:0] core_core_bus_be_i,
  output logic [2:0]                       core_core_bus_gnt_o,
  output logic [2:0]                       core_core_bus_r_opc_o,
  output logic [2:0][       DataWidth-1:0] core_core_bus_r_rdata_o,
  output logic [2:0]                       core_core_bus_r_valid_o,

  output logic [2:0][NExtPerfCounters-1:0] core_perf_counters_o

  // APU/SHARED_FPU not implemented
);

  typedef enum logic {NORMAL, TMR} redundancy_mode_e;

  redundancy_mode_e red_mode_d, red_mode_q;

  // TMR signals
  logic TMR_error;
  logic TMR_error_detect;

  localparam TOTAL_DATA_WIDTH = 5+5+32+32+DataWidth+BEWidth;
  logic [TOTAL_DATA_WIDTH-1:0] TMR_data_out;
  logic [2:0][TOTAL_DATA_WIDTH-1:0] TMR_data_in;

  logic                 core_busy;

  logic                 irq_ack;
  logic [          4:0] irq_ack_id;

  logic                 instr_req;
  logic [         31:0] instr_addr;

  logic                 data_req;
  logic [         31:0] data_add;
  logic                 data_wen;
  logic [DataWidth-1:0] data_wdata;
  logic [  BEWidth-1:0] data_be;

  // TMR Voter
  assign { core_busy,
    irq_ack, irq_ack_id,
    instr_req, instr_addr,
    data_req, data_add,
    data_wen, data_wdata,
    data_be
  } = TMR_data_out;

  assign TMR_data_in[0] = {
    core_core_busy_i[0],
    core_irq_ack_i[0], core_irq_ack_id_i[0],
    core_instr_req_i[0], core_instr_addr_i[0],
    core_core_bus_req_i[0], core_core_bus_add_i[0],
    core_core_bus_wen_i[0], core_core_bus_wdata_i[0],
    core_core_bus_be_i[0] };
  assign TMR_data_in[1] = {
    core_core_busy_i[1],
    core_irq_ack_i[1], core_irq_ack_id_i[1],
    core_instr_req_i[1], core_instr_addr_i[1],
    core_core_bus_req_i[1], core_core_bus_add_i[1],
    core_core_bus_wen_i[1], core_core_bus_wdata_i[1],
    core_core_bus_be_i[1] };
  assign TMR_data_in[2] = {
    core_core_busy_i[2],
    core_irq_ack_i[2], core_irq_ack_id_i[2],
    core_instr_req_i[2], core_instr_addr_i[2],
    core_core_bus_req_i[2], core_core_bus_add_i[2],
    core_core_bus_wen_i[2], core_core_bus_wdata_i[2],
    core_core_bus_be_i[2] };

  TMR_word_voter #(
    .DATA_WIDTH ( TOTAL_DATA_WIDTH )
  ) tcls_voter (
    .in_a      ( TMR_data_in[0]   ),
    .in_b      ( TMR_data_in[1]   ),
    .in_c      ( TMR_data_in[2]   ),
    .out       ( TMR_data_out     ),
    .error     ( TMR_error        ),
    .error_cba ( TMR_error_detect )
  );

  // TODO: implement speriph port for communication

  always_comb begin : proc_fsm
    red_mode_d = red_mode_q;  // TODO: Implement FSM logic

    for (int i = 0; i < 3; i++) begin
      core_rst_no[i] = rst_ni;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_red_mode
    if(~rst_ni) begin
      red_mode_q <= NORMAL;
    end else begin
      red_mode_q <= red_mode_d;
    end
  end

  always_comb begin : proc_ctrl_assign
    if (red_mode_q == NORMAL) begin
      for (int i = 0; i < 3; i++) begin
        core_core_id_o[i]          = intc_core_id_i[i];
        core_cluster_id_o[i]       = intc_cluster_id_i[i];

        core_clock_en_o[i]         = intc_clock_en_i[i];
        core_fetch_en_o[i]         = intc_fetch_en_i[i]; // May need config on state transition
        core_fregfile_disable_o[i] = intc_fregfile_disable_i[i];
        core_boot_addr_o[i]        = intc_boot_addr_i[i];
        core_debug_req_o[i]        = intc_debug_req_i[i];

        core_perf_counters_o[i]    = intc_perf_counters_i[i];

        intc_core_busy_o[i] = core_core_busy_i[i];
      end
    end else begin
      intc_core_busy_o[0] = core_busy;
      intc_core_busy_o[1] = '0;
      intc_core_busy_o[2] = '0;

      for (int i = 0; i < 3; i++) begin
        core_core_id_o[i]          = intc_core_id_i[0]; // TODO: implement special logic for core_id?
        core_cluster_id_o[i]       = intc_cluster_id_i[0];

        core_clock_en_o[i]         = intc_clock_en_i[0];
        core_fetch_en_o[i]         = intc_fetch_en_i[0]; // May need config on state transition
        core_fregfile_disable_o[i] = intc_fregfile_disable_i[0];
        core_boot_addr_o[i]        = intc_boot_addr_i[0]; // May need special value when restoring from tcls error
        core_debug_req_o[i]        = intc_debug_req_i[0];

        core_perf_counters_o[i]    = intc_perf_counters_i[0];
      end
    end
  end

  always_comb begin : proc_data_assign
    if (red_mode_q == NORMAL) begin
      for (int i = 0; i < 3; i++) begin
        intc_core_bus_req_o[i]    = core_core_bus_req_i[i];
        intc_core_bus_add_o[i]    = core_core_bus_add_i[i];
        intc_core_bus_wen_o[i]    = core_core_bus_wen_i[i];
        intc_core_bus_wdata_o[i]  = core_core_bus_wdata_i[i];
        intc_core_bus_be_o[i]     = core_core_bus_be_i[i];

        core_core_bus_gnt_o[i]     = intc_core_bus_gnt_i[i];
        core_core_bus_r_rdata_o[i] = intc_core_bus_r_rdata_i[i];
        core_core_bus_r_opc_o[i]   = intc_core_bus_r_opc_i[i];
        core_core_bus_r_valid_o[i] = intc_core_bus_r_valid_i[i];
      end
    end else begin
      intc_core_bus_req_o[0]    = data_req;
      intc_core_bus_add_o[0]    = data_add;
      intc_core_bus_wen_o[0]    = data_wen;
      intc_core_bus_wdata_o[0]  = data_wdata;
      intc_core_bus_be_o[0]     = data_be;
      
      intc_core_bus_req_o[1]    = '0;
      intc_core_bus_add_o[1]    = '0;
      intc_core_bus_wen_o[1]    = '0;
      intc_core_bus_wdata_o[1]  = '0;
      intc_core_bus_be_o[1]     = '0;

      intc_core_bus_req_o[2]    = '0;
      intc_core_bus_add_o[2]    = '0;
      intc_core_bus_wen_o[2]    = '0;
      intc_core_bus_wdata_o[2]  = '0;
      intc_core_bus_be_o[2]     = '0;

      for (int i = 0; i < 3; i++) begin
        core_core_bus_gnt_o[i]     = intc_core_bus_gnt_i[i];
        core_core_bus_r_rdata_o[i] = intc_core_bus_r_rdata_i[i];
        core_core_bus_r_opc_o[i]   = intc_core_bus_r_opc_i[i];
        core_core_bus_r_valid_o[i] = intc_core_bus_r_valid_i[i];
      end
    end
  
  end

  always_comb begin : proc_irq_assign
    if (red_mode_q == NORMAL) begin
      for (int i = 0; i < 3; i++) begin
        intc_irq_ack_o[i]    = core_irq_ack_i[i];
        intc_irq_ack_id_o[i] = core_irq_ack_id_i[i];

        core_irq_req_o[i] = intc_irq_req_i[i];
        core_irq_id_o[i]  = intc_irq_id_i[i];
      end
    end else begin
      // TODO: Add irq to trigger re-synchronization
      intc_irq_ack_o[0]    = irq_ack;
      intc_irq_ack_id_o[0] = irq_ack_id;

      intc_irq_ack_o[1] = '0;
      intc_irq_ack_o[2] = '0;
      intc_irq_ack_id_o[1] = '0;
      intc_irq_ack_id_o[2] = '0;
      for (int i = 0; i < 3; i++) begin
        core_irq_req_o[i] = intc_irq_req_i[0];
        core_irq_id_o[i]  = intc_irq_req_i[0];
      end
    end

  end

  always_comb begin : proc_instr_assign
    if (red_mode_q == NORMAL) begin
      for (int i = 0; i < 3; i++) begin
        intc_instr_req_o[i]  = core_instr_req_i[i];
        intc_instr_addr_o[i] = core_instr_addr_i[i];

        core_instr_gnt_o[i]     = intc_instr_gnt_i[i];
        core_instr_r_rdata_o[i] = intc_instr_r_rdata_i[i];
        core_instr_r_valid_o[i] = intc_instr_r_valid_i[i];
      end
    end else begin
      intc_instr_req_o[0]  = instr_req;
      intc_instr_addr_o[0] = instr_addr;

      intc_instr_req_o[1]  = '0;
      intc_instr_req_o[2]  = '0;
      intc_instr_addr_o[1] = '0;
      intc_instr_addr_o[2] = '0;
      for (int i = 0; i < 3; i++) begin
        core_instr_gnt_o[i]     = intc_instr_gnt_i[0];
        core_instr_r_rdata_o[i] = intc_instr_r_rdata_i[0];
        core_instr_r_valid_o[i] = intc_instr_r_valid_i[0];
      end
    end
  end


endmodule