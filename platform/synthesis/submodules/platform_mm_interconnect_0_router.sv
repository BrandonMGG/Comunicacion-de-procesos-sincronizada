// (C) 2001-2017 Intel Corporation. All rights reserved.
// Your use of Intel Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files from any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Intel Program License Subscription 
// Agreement, Intel FPGA IP License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Intel and sold by 
// Intel or its authorized distributors.  Please refer to the applicable 
// agreement for further details.



// Your use of Altera Corporation's design tools, logic functions and other 
// software and tools, and its AMPP partner logic functions, and any output 
// files any of the foregoing (including device programming or simulation 
// files), and any associated documentation or information are expressly subject 
// to the terms and conditions of the Altera Program License Subscription 
// Agreement, Altera MegaCore Function License Agreement, or other applicable 
// license agreement, including, without limitation, that your use is for the 
// sole purpose of programming logic devices manufactured by Altera and sold by 
// Altera or its authorized distributors.  Please refer to the applicable 
// agreement for further details.


// $Id: //acds/rel/17.1std/ip/merlin/altera_merlin_router/altera_merlin_router.sv.terp#1 $
// $Revision: #1 $
// $Date: 2017/07/30 $
// $Author: swbranch $

// -------------------------------------------------------
// Merlin Router
//
// Asserts the appropriate one-hot encoded channel based on 
// either (a) the address or (b) the dest id. The DECODER_TYPE
// parameter controls this behaviour. 0 means address decoder,
// 1 means dest id decoder.
//
// In the case of (a), it also sets the destination id.
// -------------------------------------------------------

`timescale 1 ns / 1 ns

module platform_mm_interconnect_0_router_default_decode
  #(
     parameter DEFAULT_CHANNEL = 1,
               DEFAULT_WR_CHANNEL = -1,
               DEFAULT_RD_CHANNEL = -1,
               DEFAULT_DESTID = 6 
   )
  (output [79 - 76 : 0] default_destination_id,
   output [15-1 : 0] default_wr_channel,
   output [15-1 : 0] default_rd_channel,
   output [15-1 : 0] default_src_channel
  );

  assign default_destination_id = 
    DEFAULT_DESTID[79 - 76 : 0];

  generate
    if (DEFAULT_CHANNEL == -1) begin : no_default_channel_assignment
      assign default_src_channel = '0;
    end
    else begin : default_channel_assignment
      assign default_src_channel = 15'b1 << DEFAULT_CHANNEL;
    end
  endgenerate

  generate
    if (DEFAULT_RD_CHANNEL == -1) begin : no_default_rw_channel_assignment
      assign default_wr_channel = '0;
      assign default_rd_channel = '0;
    end
    else begin : default_rw_channel_assignment
      assign default_wr_channel = 15'b1 << DEFAULT_WR_CHANNEL;
      assign default_rd_channel = 15'b1 << DEFAULT_RD_CHANNEL;
    end
  endgenerate

endmodule


module platform_mm_interconnect_0_router
(
    // -------------------
    // Clock & Reset
    // -------------------
    input clk,
    input reset,

    // -------------------
    // Command Sink (Input)
    // -------------------
    input                       sink_valid,
    input  [93-1 : 0]    sink_data,
    input                       sink_startofpacket,
    input                       sink_endofpacket,
    output                      sink_ready,

    // -------------------
    // Command Source (Output)
    // -------------------
    output                          src_valid,
    output reg [93-1    : 0] src_data,
    output reg [15-1 : 0] src_channel,
    output                          src_startofpacket,
    output                          src_endofpacket,
    input                           src_ready
);

    // -------------------------------------------------------
    // Local parameters and variables
    // -------------------------------------------------------
    localparam PKT_ADDR_H = 50;
    localparam PKT_ADDR_L = 36;
    localparam PKT_DEST_ID_H = 79;
    localparam PKT_DEST_ID_L = 76;
    localparam PKT_PROTECTION_H = 83;
    localparam PKT_PROTECTION_L = 81;
    localparam ST_DATA_W = 93;
    localparam ST_CHANNEL_W = 15;
    localparam DECODER_TYPE = 0;

    localparam PKT_TRANS_WRITE = 53;
    localparam PKT_TRANS_READ  = 54;

    localparam PKT_ADDR_W = PKT_ADDR_H-PKT_ADDR_L + 1;
    localparam PKT_DEST_ID_W = PKT_DEST_ID_H-PKT_DEST_ID_L + 1;



    // -------------------------------------------------------
    // Figure out the number of bits to mask off for each slave span
    // during address decoding
    // -------------------------------------------------------
    localparam PAD0 = log2ceil(64'h4000 - 64'h0); 
    localparam PAD1 = log2ceil(64'h6000 - 64'h5800); 
    localparam PAD2 = log2ceil(64'h6020 - 64'h6000); 
    localparam PAD3 = log2ceil(64'h6030 - 64'h6020); 
    localparam PAD4 = log2ceil(64'h6040 - 64'h6030); 
    localparam PAD5 = log2ceil(64'h6050 - 64'h6040); 
    localparam PAD6 = log2ceil(64'h6060 - 64'h6050); 
    localparam PAD7 = log2ceil(64'h6070 - 64'h6060); 
    localparam PAD8 = log2ceil(64'h6080 - 64'h6070); 
    localparam PAD9 = log2ceil(64'h6090 - 64'h6080); 
    localparam PAD10 = log2ceil(64'h60a0 - 64'h6090); 
    localparam PAD11 = log2ceil(64'h60b0 - 64'h60a0); 
    localparam PAD12 = log2ceil(64'h60c0 - 64'h60b0); 
    localparam PAD13 = log2ceil(64'h60d0 - 64'h60c0); 
    // -------------------------------------------------------
    // Work out which address bits are significant based on the
    // address range of the slaves. If the required width is too
    // large or too small, we use the address field width instead.
    // -------------------------------------------------------
    localparam ADDR_RANGE = 64'h60d0;
    localparam RANGE_ADDR_WIDTH = log2ceil(ADDR_RANGE);
    localparam OPTIMIZED_ADDR_H = (RANGE_ADDR_WIDTH > PKT_ADDR_W) ||
                                  (RANGE_ADDR_WIDTH == 0) ?
                                        PKT_ADDR_H :
                                        PKT_ADDR_L + RANGE_ADDR_WIDTH - 1;

    localparam RG = RANGE_ADDR_WIDTH-1;
    localparam REAL_ADDRESS_RANGE = OPTIMIZED_ADDR_H - PKT_ADDR_L;

      reg [PKT_ADDR_W-1 : 0] address;
      always @* begin
        address = {PKT_ADDR_W{1'b0}};
        address [REAL_ADDRESS_RANGE:0] = sink_data[OPTIMIZED_ADDR_H : PKT_ADDR_L];
      end   

    // -------------------------------------------------------
    // Pass almost everything through, untouched
    // -------------------------------------------------------
    assign sink_ready        = src_ready;
    assign src_valid         = sink_valid;
    assign src_startofpacket = sink_startofpacket;
    assign src_endofpacket   = sink_endofpacket;
    wire [PKT_DEST_ID_W-1:0] default_destid;
    wire [15-1 : 0] default_src_channel;




    // -------------------------------------------------------
    // Write and read transaction signals
    // -------------------------------------------------------
    wire read_transaction;
    assign read_transaction  = sink_data[PKT_TRANS_READ];


    platform_mm_interconnect_0_router_default_decode the_default_decode(
      .default_destination_id (default_destid),
      .default_wr_channel   (),
      .default_rd_channel   (),
      .default_src_channel  (default_src_channel)
    );

    always @* begin
        src_data    = sink_data;
        src_channel = default_src_channel;
        src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = default_destid;

        // --------------------------------------------------
        // Address Decoder
        // Sets the channel and destination ID based on the address
        // --------------------------------------------------

    // ( 0x0 .. 0x4000 )
    if ( {address[RG:PAD0],{PAD0{1'b0}}} == 15'h0   ) begin
            src_channel = 15'b00000000000010;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 6;
    end

    // ( 0x5800 .. 0x6000 )
    if ( {address[RG:PAD1],{PAD1{1'b0}}} == 15'h5800   ) begin
            src_channel = 15'b00000000000001;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 5;
    end

    // ( 0x6000 .. 0x6020 )
    if ( {address[RG:PAD2],{PAD2{1'b0}}} == 15'h6000   ) begin
            src_channel = 15'b00000000000100;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 14;
    end

    // ( 0x6020 .. 0x6030 )
    if ( {address[RG:PAD3],{PAD3{1'b0}}} == 15'h6020  && read_transaction  ) begin
            src_channel = 15'b10000000000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 4;
    end

    // ( 0x6030 .. 0x6040 )
    if ( {address[RG:PAD4],{PAD4{1'b0}}} == 15'h6030  && read_transaction  ) begin
            src_channel = 15'b01000000000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 3;
    end

    // ( 0x6040 .. 0x6050 )
    if ( {address[RG:PAD5],{PAD5{1'b0}}} == 15'h6040  && read_transaction  ) begin
            src_channel = 15'b00100000000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 2;
    end

    // ( 0x6050 .. 0x6060 )
    if ( {address[RG:PAD6],{PAD6{1'b0}}} == 15'h6050  && read_transaction  ) begin
            src_channel = 15'b00010000000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 1;
    end

    // ( 0x6060 .. 0x6070 )
    if ( {address[RG:PAD7],{PAD7{1'b0}}} == 15'h6060  && read_transaction  ) begin
            src_channel = 15'b00001000000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 0;
    end

    // ( 0x6070 .. 0x6080 )
    if ( {address[RG:PAD8],{PAD8{1'b0}}} == 15'h6070   ) begin
            src_channel = 15'b00000100000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 13;
    end

    // ( 0x6080 .. 0x6090 )
    if ( {address[RG:PAD9],{PAD9{1'b0}}} == 15'h6080   ) begin
            src_channel = 15'b00000010000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 12;
    end

    // ( 0x6090 .. 0x60a0 )
    if ( {address[RG:PAD10],{PAD10{1'b0}}} == 15'h6090   ) begin
            src_channel = 15'b00000001000000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 11;
    end

    // ( 0x60a0 .. 0x60b0 )
    if ( {address[RG:PAD11],{PAD11{1'b0}}} == 15'h60a0   ) begin
            src_channel = 15'b00000000100000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 10;
    end

    // ( 0x60b0 .. 0x60c0 )
    if ( {address[RG:PAD12],{PAD12{1'b0}}} == 15'h60b0   ) begin
            src_channel = 15'b00000000010000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 9;
    end

    // ( 0x60c0 .. 0x60d0 )
    if ( {address[RG:PAD13],{PAD13{1'b0}}} == 15'h60c0   ) begin
            src_channel = 15'b00000000001000;
            src_data[PKT_DEST_ID_H:PKT_DEST_ID_L] = 8;
    end

end


    // --------------------------------------------------
    // Ceil(log2()) function
    // --------------------------------------------------
    function integer log2ceil;
        input reg[65:0] val;
        reg [65:0] i;

        begin
            i = 1;
            log2ceil = 0;

            while (i < val) begin
                log2ceil = log2ceil + 1;
                i = i << 1;
            end
        end
    endfunction

endmodule

