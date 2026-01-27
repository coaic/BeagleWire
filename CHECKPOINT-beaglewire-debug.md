# BeagleWire Debugging Checkpoint

**Date:** January 26, 2026  
**System:** BeagleBone Black with BeagleWire cape  
**OS:** Debian Trixie, Kernel 6.18.6-bone16  

---

## Current Status

- SPI device `/dev/spidev1.0` exists and is accessible
- GPIO control via `gpioset -c 2 21=X` appears to work (no errors)
- **Problem:** Cannot read JEDEC ID from SPI flash - always returns `0x00 0x00 0x00 0x00`
- Kernel does NOT have FPGA subsystem enabled (`CONFIG_FPGA is not set`)

## What We've Established

1. **SPI Bus Topology (from schematic):**
   - BeagleBone SPI1, FPGA config pins (U1F), and Flash (U5) are ALL on the same bus
   - SPI_MISO connects to: P9_29, FPGA pin 67, Flash pin 5
   - When FPGA CRESET is low, it should tri-state and allow direct flash access

2. **GPIO Mapping:**
   - P9_25 = gpiochip2, line 21 (for CRESET control)
   - CRESET is directly low (directly connect CRESET to FPGA via JP2 jumper)
   - JP1 and JP2 jumpers ARE installed

3. **Tools Working:**
   - `gpioset`, `gpioget` (gpiod package)
   - `python3-spidev`
   - `flashrom`
5. **Tests Performed:**
   - With BBB booted up P9_25 reads 2.8v
   - sudo gpioset -z -c 2 21=0 - P9_25 reads 0.0v
   - sudo pkill gpioset; sudo gpioset -z -c 2 21=1 P9_25 reads 3.3v

---

## Questions to Answer Next Session

### Hardware Verification (need multimeter):

1. **With CRESET held low** (`sudo gpioset -z -c 2 21=0 &`):
   - What's the voltage on **P9_25**? (Should be ~0V)
   - What's the voltage on **FPGA pin 66** (CRESET_B)? (Should also be ~0V)

2. **With CRESET released** (`sudo gpioset -c 2 21=1`):
   - What's the voltage on **P9_25**? (Should be ~3.3V)
   - What's the voltage on **FPGA pin 66**? (Should also be ~3.3V)

3. **Check continuity** between P9_25 and FPGA pin 66 (through JP2)

4. **Check SPI signals with scope/logic analyzer** (if available):
   - Is clock appearing on P9_31 during SPI transactions?
   - Is CS (P9_28) going low during transactions?
   - Is data appearing on MOSI (P9_30)?

### Software Verification:

5. **Is pin muxing correct?** The SPI pins might need to be explicitly muxed:
   ```bash
   # Check current pin modes
   cat /sys/kernel/debug/pinctrl/44e10800.pinmux-pinctrl-single/pinmux-pins | grep -E "(28|29|30|31)"
   
   # Or if config-pin is available:
   config-pin -q P9_28
   config-pin -q P9_29
   config-pin -q P9_30
   config-pin -q P9_31
   config-pin -q P9_25
   ```

6. **Is the SPI driver actually sending data?**
   ```bash
   # Monitor SPI with logic analyzer or scope while running:
   sudo python3 -c "
   import spidev
   spi = spidev.SpiDev()
   spi.open(1, 0)
   spi.max_speed_hz = 100000
   spi.xfer([0xAA, 0x55, 0xAA, 0x55])  # Recognizable pattern
   spi.close()
   "
   ```

---

## Possible Root Causes

1. **GPIO not actually controlling CRESET** - pin mux issue or wrong GPIO
2. **SPI not actually transmitting** - driver issue or pin mux
3. **Flash chip in bad state** - might need power cycle
4. **FPGA not tri-stating** - even in reset, something holding bus
5. **Hardware issue** - bad solder joint, damaged trace

---

## Commands to Run Next Session

```bash
# 1. Full diagnostic with multimeter ready
sudo gpioset -z -c 2 21=0 &
# MEASURE: P9_25 voltage, FPGA pin 66 voltage
# Expected: Both ~0V

sudo pkill gpioset
sudo gpioset -c 2 21=1
# MEASURE: P9_25 voltage, FPGA pin 66 voltage  
# Expected: Both ~3.3V

# 2. Check pin muxing
cat /sys/kernel/debug/pinctrl/44e10800.pinmux-pinctrl-single/pinmux-pins 2>/dev/null | head -50

# 3. Try flashrom directly (it might give better error messages)
sudo pkill gpioset
sudo gpioset -z -c 2 21=0 &
sleep 1
sudo flashrom -p linux_spi:dev=/dev/spidev1.0,spispeed=1000000 -V
sudo pkill gpioset

# 4. Power cycle the entire board and try again
# Sometimes the flash gets stuck in a bad state
```

---

## Files Created This Session

| File | Purpose |
|------|---------|
| `ice40prog.c` | Userspace FPGA programmer (C, uses libgpiod) |
| `Makefile` | Build ice40prog |
| `README.md` | Usage instructions for ice40prog |
| `bw-spi-flash.sh` | Modern equivalent of bw_spi.sh (programs flash) |
| `bw-sram-prog.sh` | Direct SRAM programming script |
| `tool-equivalents.md` | Old vs new tool reference |
| `beaglewire-ice40.dts` | Device tree overlay (draft, needs kernel FPGA support) |
| `beaglewire-setup-guide.md` | General setup guide |

---

## Key Documentation References

- **Lattice FPGA-TN-02001** - iCE40 Programming and Configuration
  - SPI Slave Configuration: Section 13, Appendix A
  - Timing: 200ns CRESET pulse, 1200µs housekeeping wait, 49 post-config clocks
  
- **BeagleWire Schematic** - Your uploaded PDF
  - Flash: U5 (M25PX32-VMW)
  - FPGA: U1 (iCE40HX4K-TQ144)
  - Jumpers: JP1 (CDONE), JP2 (CRESET)

---

## Next Steps Summary

1. ✅ Verify GPIO is actually toggling voltage on P9_25
2. ✅ Verify CRESET signal reaches FPGA pin 66
3. ✅ Verify SPI signals are actually being transmitted
4. ⬜ If all electrical checks pass, try `flashrom -V` for verbose output
5. ⬜ Consider power cycling the board
6. ⬜ If flash works, test with actual bitstream
