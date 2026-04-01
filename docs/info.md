<!---
This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This chip generates a **real-time SIRDS autostereogram** (Magic Eye style) on a VGA monitor, driven by a live depth map streamed from a Raspberry Pi camera.

### Block diagram

```
Raspberry Pi                          TT Chip (2×1 tile)
┌──────────────┐                    ┌──────────────────────────────┐
│  Pi Camera   │                    │                              │
│  ↓           │  ui_in[3:0]        │  stereogram_core             │
│  Depth Est.  │ ──4-bit depth────► │  ┌────────────────────────┐  │
│  ↓           │                    │  │ 32×6-bit shift register│  │
│  DMA GPIO    │◄── pclk_out ──────  │  │ + deterministic hash   │  │  uo_out[7:0]
│  out at 25   │◄── active ────────  │  └────────────────────────┘  │ ──────────►  VGA monitor
│  MHz pixel   │◄── frame_start ──   │  ↕                           │  (TinyVGA
│  rate        │◄── line_start ───   │  vga_sync (640×480@60 Hz)    │   PMOD)
└──────────────┘                    └──────────────────────────────┘
```

### Stereogram algorithm

For each scanline the chip divides pixels into two regions:

1. **Seed region** (x < 32): output a deterministic pseudo-random 6-bit colour from a combinational hash of `(hcount, vcount)`. The hash is stable across frames so the pattern does not flicker.

2. **Stereogram region** (x ≥ 32): output a copy of the pixel `sep` positions to the left, where:
   ```
   sep = 32 − depth[3:2]   →   29..32 pixels
   ```
   This small disparity in the repeating pattern creates the illusion of depth when the viewer relaxes focus beyond the screen.

A 32-entry × 6-bit shift register (192 flip-flops) holds the required pixel history. The `sep` computation maps 4-bit depth to 4 discrete disparity levels.

### VGA output

640×480 at 60 Hz via the **TinyVGA PMOD** (2 bits per colour channel, 64 colours, active-low sync).

| uo_out bit | Signal |
|-----------|--------|
| 0         | R1     |
| 1         | G1     |
| 2         | B1     |
| 3         | VSYNC  |
| 4         | R0     |
| 5         | G0     |
| 6         | B0     |
| 7         | HSYNC  |

### Pi camera depth interface

The chip exposes four sync signals on `uio_out[3:0]` so the Pi knows exactly when to present each depth value:

| uio_out | Signal      | Purpose                                       |
|---------|-------------|-----------------------------------------------|
| 0       | pclk_out    | 25 MHz pixel clock; Pi drives depth on ↑      |
| 1       | frame_start | 1-cycle pulse at pixel (0,0) of every frame   |
| 2       | line_start  | 1-cycle pulse at first pixel of each row      |
| 3       | active      | High during the 640×480 visible area          |

Pi workflow:
1. Wait for `frame_start` to preload the DMA buffer with a new depth frame.
2. When `active` is high, use hardware SPI / DMA GPIO to clock out 4-bit depth values on each rising edge of `pclk_out`.
3. `line_start` can trigger per-row depth refresh for line-by-line depth sources (e.g. VL53L5CX row scan).

## How to test

1. Connect a VGA monitor to the TinyVGA PMOD on `uo_out`.
2. Connect a Raspberry Pi:
   - Pi GPIO pins → `ui_in[3:0]` (4-bit depth, LSB first)
   - `uio_out[0..3]` → Pi GPIO inputs (sync signals)
3. Run the Pi depth-streaming script (see README).
4. Point the camera at a scene. Objects closer to the camera should appear to "pop out" of the random-dot pattern when the viewer focuses beyond the screen surface.

**Quick smoke-test without Pi:** Tie `ui_in[3:0]` to a fixed value. A flat-colour-dot pattern appears at depth=0 (no 3D), or the pattern repeats with maximum disparity at depth=15 (maximum pop-out effect visible).

## External hardware

### Required
- **TinyVGA PMOD** – plugs into the `uo_out` PMOD connector. Converts 2-bit-per-channel digital RGB + sync to analogue VGA.
- **Raspberry Pi 4 or Pi 5** – computes or captures depth map and streams it to the chip.
- **Pi Camera** (any model compatible with the Pi in use).

### Recommended depth sources (best quality → simplest)

The chip only needs a 4-bit depth map; the Pi provides it. Better depth = better 3D effect.

| Option | Hardware | 3D quality | Notes |
|--------|----------|------------|-------|
| **A – easiest** | Pi Camera only | ★★★☆ | Pi runs MiDaS monocular depth estimation. ~5 fps on Pi 4, ~15 fps on Pi 5. No extra parts needed. |
| **B – recommended** | Pi Camera + **VL53L5CX** ToF sensor | ★★★★ | ST Microelectronics 8×8 depth matrix, up to 60 fps over I2C, ~$10. Pi bilinearly upscales depth to match frame. Low latency, good for live demos. |
| **C – best quality** | Stereo Pi Camera rig | ★★★★★ | Two Pi cameras + OpenCV stereo disparity map. Full-resolution depth, requires calibration. |

**Recommendation:** Start with option A (Pi Camera + MiDaS) to validate the system. Add a VL53L5CX (option B) for smooth live-performance demos where low latency matters.
