// SPDX-FileCopyrightText: 2025 dvirdc
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// VGA timing generator: 640x480 @ 60 Hz, 25 MHz pixel clock
// Horizontal: 640 active + 16 FP + 96 sync + 48 BP = 800 total
// Vertical:   480 active + 10 FP +  2 sync + 33 BP = 525 total
// Both sync pulses are active-low (standard for this mode)

module vga_sync (
    input  wire        pclk,
    input  wire        rst_n,
    output reg  [9:0]  hcount,       // 0..799
    output reg  [9:0]  vcount,       // 0..524
    output wire        hsync,        // active-low
    output wire        vsync,        // active-low
    output wire        active,       // high during visible area
    output wire        frame_start,  // 1-cycle pulse at pixel (0,0)
    output wire        line_start    // 1-cycle pulse at first pixel of each active row
);
    localparam H_ACTIVE = 640;
    localparam H_FP     = 16;
    localparam H_SYNC_W = 96;
    localparam H_BP     = 48;
    localparam H_TOTAL  = 800;

    localparam V_ACTIVE = 480;
    localparam V_FP     = 10;
    localparam V_SYNC_W = 2;
    localparam V_BP     = 33;
    localparam V_TOTAL  = 525;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hcount <= 10'd0;
            vcount <= 10'd0;
        end else if (hcount == H_TOTAL - 1) begin
            hcount <= 10'd0;
            vcount <= (vcount == V_TOTAL - 1) ? 10'd0 : vcount + 10'd1;
        end else begin
            hcount <= hcount + 10'd1;
        end
    end

    wire h_active_w = (hcount < H_ACTIVE);
    wire v_active_w = (vcount < V_ACTIVE);

    assign active      = h_active_w && v_active_w;
    assign hsync       = ~(hcount >= H_ACTIVE + H_FP &&
                           hcount <  H_ACTIVE + H_FP + H_SYNC_W);
    assign vsync       = ~(vcount >= V_ACTIVE + V_FP &&
                           vcount <  V_ACTIVE + V_FP + V_SYNC_W);
    assign frame_start = (hcount == 10'd0) && (vcount == 10'd0);
    assign line_start  = (hcount == 10'd0) && v_active_w;

endmodule
