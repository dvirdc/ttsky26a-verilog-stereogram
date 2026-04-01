// SPDX-FileCopyrightText: 2025 dvirdc
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// Raspberry Pi Camera → VGA Stereogram Engine
//
// The chip generates a 640×480 SIRDS (autostereogram / Magic Eye) on a
// VGA monitor, using a real-time 4-bit depth map streamed from a
// Raspberry Pi over a simple parallel GPIO interface.
//
// ── Output ──────────────────────────────────────────────────────────
//  uo_out  → TinyVGA PMOD (plug into VGA monitor)
//    [0] R1  [1] G1  [2] B1  [3] VSYNC
//    [4] R0  [5] G0  [6] B0  [7] HSYNC
//
// ── Depth input (from Raspberry Pi) ─────────────────────────────────
//  ui_in[3:0]  4-bit depth, sampled on each rising pclk edge while
//              active is high.  0 = background, 15 = foreground.
//              Pi must drive these in pixel order, left-to-right then
//              top-to-bottom, gated by the active and pclk signals
//              exposed on uio_out.
//
// ── Pi synchronisation outputs ──────────────────────────────────────
//  uio_out[0]  pclk       25 MHz pixel clock (Pi samples depth on ↑)
//  uio_out[1]  frame_start  1-cycle pulse at pixel (0,0) of every frame
//  uio_out[2]  line_start   1-cycle pulse at first pixel of each row
//  uio_out[3]  active       high during visible 640×480 area
//  uio_oe[3:0] = 4'b1111 (all four are outputs)
//
// ── Clock ────────────────────────────────────────────────────────────
//  System clock:  50 MHz (from Tiny Tapeout)
//  Pixel clock:   25 MHz  (÷2, sufficient for 640×480@60 Hz)

module tt_um_ttsky26a_stereogram (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    // ------------------------------------------------------------------
    // Pixel clock: 50 MHz ÷ 2 = 25 MHz
    // ------------------------------------------------------------------
    reg pclk;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) pclk <= 1'b0;
        else        pclk <= ~pclk;

    // ------------------------------------------------------------------
    // VGA timing
    // ------------------------------------------------------------------
    wire [9:0] hcount, vcount;
    wire       hsync, vsync, active, frame_start, line_start;

    vga_sync vga_inst (
        .pclk        (pclk),
        .rst_n       (rst_n),
        .hcount      (hcount),
        .vcount      (vcount),
        .hsync       (hsync),
        .vsync       (vsync),
        .active      (active),
        .frame_start (frame_start),
        .line_start  (line_start)
    );

    // ------------------------------------------------------------------
    // Stereogram core
    // ------------------------------------------------------------------
    wire [5:0] pixel;

    stereogram_core #(
        .SEED_W  (32),
        .SEP_MAX (32),
        .SEP_MIN (29)
    ) stereo_inst (
        .pclk       (pclk),
        .rst_n      (rst_n),
        .active     (active),
        .line_start (line_start),
        .hcount     (hcount),
        .vcount     (vcount[8:0]),
        .depth      (ui_in[3:0]),
        .pixel_out  (pixel)
    );

    // ------------------------------------------------------------------
    // TinyVGA PMOD output
    // Pinout: [0]=R1 [1]=G1 [2]=B1 [3]=VSYNC [4]=R0 [5]=G0 [6]=B0 [7]=HSYNC
    // pixel: [1:0]=R  [3:2]=G  [5:4]=B
    // Blank colour channels outside active area (sync signals always pass through)
    // ------------------------------------------------------------------
    wire [1:0] r = active ? pixel[1:0] : 2'b00;
    wire [1:0] g = active ? pixel[3:2] : 2'b00;
    wire [1:0] b = active ? pixel[5:4] : 2'b00;

    assign uo_out = {hsync, b[0], g[0], r[0], vsync, b[1], g[1], r[1]};

    // ------------------------------------------------------------------
    // Synchronisation outputs to Pi
    // ------------------------------------------------------------------
    assign uio_out = {4'b0000, active, line_start, frame_start, pclk};
    assign uio_oe  = 8'b00001111;

    wire _unused = &{ena, uio_in, 1'b0};

endmodule
