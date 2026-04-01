# SPDX-FileCopyrightText: 2025 dvirdc
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


VGA_H_TOTAL  = 800
VGA_V_ACTIVE = 480
VGA_V_TOTAL  = 525


@cocotb.test()
async def test_vga_sync(dut):
    """Verify that HSYNC pulses occur at the correct period."""
    dut._log.info("Start: VGA sync test")
    clock = Clock(dut.clk, 20, unit="ns")  # 50 MHz
    cocotb.start_soon(clock.start())

    dut.ena.value    = 1
    dut.ui_in.value  = 0   # depth = 0 (flat background)
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1

    # Each pixel clock = 2 system clocks (50 MHz -> 25 MHz).
    # Run for 3 complete scanlines = 3 * 800 = 2400 pixel clocks
    # = 4800 system clocks.
    LINES     = 3
    PIX_CLKS  = LINES * VGA_H_TOTAL
    SYS_CLKS  = PIX_CLKS * 2

    hsync_low_count = 0
    for _ in range(SYS_CLKS):
        await RisingEdge(dut.clk)
        if int(dut.uo_out.value) >> 7 == 0:   # uo_out[7] = HSYNC (active-low)
            hsync_low_count += 1

    dut._log.info(f"HSYNC low for {hsync_low_count} system-clock cycles over {LINES} lines")

    # HSYNC sync pulse = 96 pixel clocks = 192 system clocks per line.
    # Over 3 lines: 3 * 192 = 576 system-clock cycles expected (±a few for edge effects).
    assert 550 <= hsync_low_count <= 620, \
        f"Unexpected HSYNC low count: {hsync_low_count} (expected ~576)"
    dut._log.info("VGA sync test PASSED")


@cocotb.test()
async def test_depth_encoding(dut):
    """Check that different depth inputs produce different pixel outputs."""
    dut._log.info("Start: depth encoding test")
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    dut.ena.value    = 1
    dut.ui_in.value  = 0
    dut.uio_in.value = 0
    dut.rst_n.value  = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value  = 1

    # Skip to the first active area: VGA counters start at (0,0) after reset,
    # so the first active pixel appears immediately.
    # Skip the seed region (32 pixels = 64 system clocks) then capture
    # several pixels at depth=0 and depth=15.

    SEED_CLKS = 32 * 2   # 32 pixel clocks * 2 sys-clocks each

    # Collect outputs with depth=0 (flat background, max separation)
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, SEED_CLKS)
    pixels_depth0 = []
    for _ in range(8):
        await ClockCycles(dut.clk, 2)
        pixels_depth0.append(int(dut.uo_out.value) & 0b00111111)  # RGB bits only

    # Reset and repeat with depth=15 (foreground, min separation)
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    dut.ui_in.value = 0b00001111  # depth = 15

    await ClockCycles(dut.clk, SEED_CLKS)
    pixels_depth15 = []
    for _ in range(8):
        await ClockCycles(dut.clk, 2)
        pixels_depth15.append(int(dut.uo_out.value) & 0b00111111)

    dut._log.info(f"depth=0  pixels: {pixels_depth0}")
    dut._log.info(f"depth=15 pixels: {pixels_depth15}")

    # With different depths, the copy-back positions differ by 3 pixels,
    # so at least some outputs should differ.
    assert pixels_depth0 != pixels_depth15, \
        "depth=0 and depth=15 produced identical pixel streams – check sep logic"
    dut._log.info("Depth encoding test PASSED")
