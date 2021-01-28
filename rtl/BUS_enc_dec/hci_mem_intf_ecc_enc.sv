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
// Adds SECDED ECC to hci_mem_intf

module hci_mem_intf_ecc_enc #(
  parameter  int unsigned DW          = 32,
  parameter  int unsigned UW          = 0,
  localparam int unsigned NB_ECC_BITS = (DW==32) ? 7 : 8   // currently 7bit for DW=32, 8bit for DW=64
) (
  hci_mem_intf.slave  bus_in,
  hci_mem_intf.master bus_out,
  output logic [NB_ECC_BITS-1:0] syndrome_o,
  output logic [1:0]             err_o
);

  // ECC is added to the higher bits of USER signals, calculated from dat bits.
  // No management of failed ECC correction is done here.

  localparam ECC_USER_WIDTH = UW + NB_ECC_BITS;

  assign bus_out.req          = bus_in.req;
  assign bus_in.gnt           = bus_out.gnt;
  assign bus_out.add          = bus_in.add;
  assign bus_out.wen          = bus_in.wen;
  // assign bus_out.data         = bus_in.data; // add ecc below
  assign bus_out.user[UW-1:0] = bus_in.user[UW-1:0]; // add ecc below
  assign bus_out.be           = bus_in.be;
  // assign bus_in.r_data        = bus_out.r_data; // remove ecc below
  assign bus_in.r_user        = bus_out.r_user[UW-1:0]; // remove ecc below
  assign bus_in.r_valid       = bus_out.r_valid;


  if (DW == 32) begin
    prim_secded_39_32_enc ecc_encode (
      .in  ( bus_in.wata                    ),
      .out ( {bus_out.user[ECC_USER_WIDTH-1:UW], bus_out.data} )
    );

    prim_secded_39_32_dec ecc_decode (
      .in         ( {bus_out.r_user[ECC_USER_WIDTH-1:UW], bus_out.r_data} ), //rdata
      .d_o        ( bus_in.r_data ),
      .syndrome_o ( syndrome_o    ),
      .err_o      ( err_o         )
    );
  end else if (DW == 64) begin
    prim_secded_72_64_enc ecc_encode (
      .in  ( bus_in.data                    ),
      .out ( {bus_out.user[ECC_USER_WIDTH-1:UW], bus_out.data} )
    );

    prim_secded_72_64_dec ecc_decode (
      .in         ( {bus_out.r_user[ECC_USER_WIDTH-1:UW], bus_out.r_data} ), //rdata
      .d_o        ( bus_in.r_data ),
      .syndrome_o ( syndrome_o    ),
      .err_o      ( err_o         )
    );
  end else begin
    $fatal(1, "please chose appropriate DW or update the code.");
  end


endmodule