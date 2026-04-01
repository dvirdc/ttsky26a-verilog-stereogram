// SPDX-FileCopyrightText: 2025 dvirdc
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// Texture-stereogram core using a live grayscale camera feed.
//
// Algorithm (per scanline, left-to-right):
//
//   Seed region  (x < SEED_W):
//     pixel[x] = {gray_in, gray_in, gray_in}
//     -- The Pi streams the camera's 2-bit grayscale value for column x.
//        The tile width (SEED_W = SEP_MAX = 64) is one full period, so
//        the viewer sees the camera image tiling across the screen.
//
//   Stereogram region  (x >= SEED_W):
//     sep      = SEP_MAX - depth[3:1]     (8 levels, 57..64 pixels)
//     pixel[x] = sr[sep-1]               (copy from sep pixels back)
//     -- The Pi streams the 4-bit depth for every column.  Only the
//        top 3 bits (depth[3:1]) are used, giving 8 disparity levels.
//
//   After every pixel, pixel[x] is pushed into the 64-entry shift
//   register; the oldest entry is replaced.
//
// depth = 0  → sep = 64 → flat background (no disparity, same as tile)
// depth = 15 → sep = 57 → maximum pop-out (7-pixel disparity)
//
// Resource usage: 64 × 6 = 384 flip-flops for the shift register.

module stereogram_core #(
    parameter SEED_W  = 64,   // tile width = one full repeating period
    parameter SEP_MAX = 64,   // separation at depth 0  ← must equal SEED_W
    parameter SEP_MIN = 57    // separation at depth 15
) (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        active,
    input  wire        line_start,   // high for first pixel of every active row
    input  wire [9:0]  hcount,
    input  wire [3:0]  depth,        // 0 = far, 15 = near; sampled each active pixel
    input  wire [1:0]  gray_in,      // 2-bit camera grayscale for seed region
    output reg  [5:0]  pixel_out     // {B[1:0], G[1:0], R[1:0]}
);
    // ------------------------------------------------------------------
    // Gray seed pixel: replicate 2-bit luminance across all three channels
    // {B[1:0], G[1:0], R[1:0]} = {gray, gray, gray}
    // ------------------------------------------------------------------
    wire [5:0] gray_pixel = {gray_in, gray_in, gray_in};

    // ------------------------------------------------------------------
    // Separation (8 levels).
    //   sep      = SEP_MAX - depth[3:1]   →   57..64
    //   sr_idx   = sep - 1                →   56..63
    // Using depth[3:1] keeps the interface simple: the Pi sends 4-bit
    // depth and we use the top 3 bits, giving 8 evenly spaced levels.
    // ------------------------------------------------------------------
    wire [5:0] sep    = SEP_MAX - {2'b00, depth[3:1]};   // 57..64
    wire [5:0] sr_idx = sep - 6'd1;                       // 56..63

    // ------------------------------------------------------------------
    // Shift register: SEP_MAX entries × 6 bits
    //   sr[0]          = most recently pushed pixel
    //   sr[SEP_MAX-1]  = pixel pushed SEP_MAX cycles ago
    // ------------------------------------------------------------------
    reg [5:0] sr [0:SEP_MAX-1];

    wire in_seed       = (hcount < SEED_W);
    wire [5:0] computed = in_seed ? gray_pixel : sr[sr_idx];

    integer i;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < SEP_MAX; i = i + 1)
                sr[i] <= 6'd0;
            pixel_out <= 6'd0;
        end else if (active) begin
            pixel_out <= computed;

            if (line_start) begin
                // Start of row: clear sr[1..SEP_MAX-1] so last-row
                // pixels never contaminate the new row's seed.
                sr[0] <= computed;
                for (i = 1; i < SEP_MAX; i = i + 1)
                    sr[i] <= 6'd0;
            end else begin
                sr[0] <= computed;
                for (i = 1; i < SEP_MAX; i = i + 1)
                    sr[i] <= sr[i-1];
            end
        end
    end

endmodule
