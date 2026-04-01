// SPDX-FileCopyrightText: 2025 dvirdc
// SPDX-License-Identifier: Apache-2.0

`default_nettype none

// SIRDS (Single Image Random Dot Stereogram) core.
//
// Algorithm (per scanline, left-to-right):
//
//   For x = 0 .. SEED_W-1  (seed region):
//     pixel[x] = rand_color(x, y)   -- deterministic hash, stable across frames
//
//   For x = SEED_W .. 639  (stereogram region):
//     sep      = SEP_MAX - (depth[3:2])   -- 4 discrete depths → 29..32
//     pixel[x] = sr[sep-1]               -- copy from sep pixels back
//
//   After every pixel: push pixel[x] into shift register sr[0],
//                      shift existing entries toward sr[SEP_MAX-1].
//
// Viewing: cross your eyes slightly (or "look through" the screen).
// depth=0  → background / flat      (sep=32, no disparity)
// depth=15 → foreground / pop-out   (sep=29, max disparity)
//
// Resource usage: 32 × 6 = 192 flip-flops for the shift register.

module stereogram_core #(
    parameter SEED_W  = 32,   // width of per-row random seed region (pixels)
    parameter SEP_MAX = 32,   // separation at depth 0 (background)  ← must equal SR depth
    parameter SEP_MIN = 29    // separation at depth 15 (foreground)
) (
    input  wire        pclk,
    input  wire        rst_n,
    input  wire        active,
    input  wire        line_start,  // high for first pixel of every active row
    input  wire [9:0]  hcount,
    input  wire [8:0]  vcount,
    input  wire [3:0]  depth,       // 0 = far, 15 = near; sampled each active pixel
    output reg  [5:0]  pixel_out    // {B[1:0], G[1:0], R[1:0]}
);
    // ------------------------------------------------------------------
    // Deterministic per-position color hash
    // Produces stable, pseudo-random 6-bit color from (hcount, vcount).
    // Uses bit-mixing to break up spatial regularity.
    // ------------------------------------------------------------------
    wire [5:0] h6 = hcount[5:0];
    wire [5:0] v6 = vcount[5:0];
    wire [5:0] mix0 = h6 ^ v6;
    wire [5:0] mix1 = {mix0[2:0], mix0[5:3]} ^ {v6[1:0], h6[5:2]};
    wire [5:0] rand_color = mix0 ^ mix1 ^ {h6[0], v6[5:1]};

    // ------------------------------------------------------------------
    // Separation: 4 levels, one per pair of depth bits [3:2]
    //   depth[3:2] = 00 → sep = 32   (background / flat)
    //   depth[3:2] = 01 → sep = 31
    //   depth[3:2] = 10 → sep = 30
    //   depth[3:2] = 11 → sep = 29   (foreground / pop-out)
    //
    // sr_idx = sep - 1  → 28..31 (index into shift register)
    // ------------------------------------------------------------------
    wire [4:0] sep    = SEP_MAX - {1'b0, depth[3:2]};   // 29..32
    wire [4:0] sr_idx = sep - 5'd1;                      // 28..31

    // ------------------------------------------------------------------
    // Shift register: SEP_MAX entries × 6 bits
    //   sr[0]          = most recently pushed pixel
    //   sr[SEP_MAX-1]  = pixel pushed SEP_MAX cycles ago
    // ------------------------------------------------------------------
    reg [5:0] sr [0:SEP_MAX-1];

    wire in_seed      = (hcount < SEED_W);
    wire [5:0] computed = in_seed ? rand_color : sr[sr_idx];

    integer i;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < SEP_MAX; i = i + 1)
                sr[i] <= 6'd0;
            pixel_out <= 6'd0;
        end else if (active) begin
            pixel_out <= computed;

            if (line_start) begin
                // Start of row: clear sr[1..SEP_MAX-1] to prevent
                // cross-row contamination; sr[0] gets the first pixel.
                sr[0] <= computed;
                for (i = 1; i < SEP_MAX; i = i + 1)
                    sr[i] <= 6'd0;
            end else begin
                // Normal pixel: shift and insert
                sr[0] <= computed;
                for (i = 1; i < SEP_MAX; i = i + 1)
                    sr[i] <= sr[i-1];
            end
        end
    end

endmodule
