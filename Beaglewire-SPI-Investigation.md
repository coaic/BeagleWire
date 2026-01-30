# BeagleWire SPI Investigation Checkpoint

## Date: January 30, 2026

## Summary
BBB SPI1 driver is broken in kernel 6.18.6-bone16. The SPI peripheral never enables the channel, so no clock is generated. This is a kernel regression, not a BeagleWire hardware issue.

## Environment
- **Board**: BeagleBone Black
- **OS**: Debian Trixie
- **Kernel**: 6.18.6-bone16 (installed Jan 22, 2026)
- **Cape**: BeagleWire (iCE40HX4K FPGA + M25PX32 SPI flash)
- **Overlay**: BB-SPIDEV1-00A0.dtbo

## Symptoms
- SPI flash returns 0xFF for all reads (JEDEC ID, status register, etc.)
- No SPI clock generated on P9_31
- flashrom fails: "No EEPROM/flash device found"
- Problem exists with or without cape installed

## Root Cause
The omap2_mcspi driver never sets CH0CTRL bit 0 (EN) to enable the SPI channel:
```
CH0CTRL: 0x00000006  (EN bit = 0, should be 1 during transfer)
```

SPI registers show:
- SYSCONFIG: 0x00000015
- SYSSTATUS: 0x00000001
- MODULCTRL: 0x00000000
- CH0CONF: 0x00000001 (changes to 0x00000000)
- CH0STAT: 0x200103fc
- CH0CTRL: 0x00000006 (never becomes 0x01 or 0x07)

## What Works
- Pin muxing is correct (mode 3 for SPI1)
- /dev/spidev1.0 and /dev/spidev1.1 exist
- SPI module clock is enabled when accessed
- Overlay loads correctly
- All 4 SPI pins claimed by driver

## What Doesn't Work
- SPI channel never enables
- No clock output on P9_31
- No data transfer occurs

## Verified Hardware
- BeagleWire cape SPI flash (U5) has correct voltages:
  - VCC (pin 8): 3.3V
  - VSS (pin 4): 0V
  - HOLD# (pin 7): 3.3V
  - W# (pin 3): 3.3V
- CRESET GPIO control works (P9_25 / GPIO 2_21)
- Cape worked with flashrom before Jan 22 kernel update

## Key Evidence
1. Cape removed, SPI loopback test: no clock on P9_31
2. SPI register dump shows CH0CTRL EN bit never set
3. flashrom -V shows all probe attempts return 0xFF
4. Same overlay worked before kernel 6.18.6-bone16

## To Resume Investigation

### Check for kernel update:
```bash
sudo apt update
apt-cache policy bbb.io-kernel-6.18-bone
```

### Test if SPI works after update:
```bash
# With cape installed and BB-SPIDEV1-00A0.dtbo in uEnv.txt:
sudo python3 -c "
import spidev
spi = spidev.SpiDev()
spi.open(1, 0)
spi.max_speed_hz = 100000
result = spi.xfer([0x9F, 0x00, 0x00, 0x00])
print('JEDEC ID:', [hex(b) for b in result])
spi.close()
"
# Should return something other than 0xFF 0xFF 0xFF 0xFF
# M25PX32 expected: 0x20 0x71 0x16
```

### Quick SPI clock test (with scope on P9_31):
```bash
sudo python3 -c "
import spidev
spi = spidev.SpiDev()
spi.open(1, 0)
spi.max_speed_hz = 50000
for i in range(10):
    spi.xfer([0xAA])
    import time; time.sleep(0.2)
spi.close()
"
# Should see clock pulses on P9_31
```

## Working Configuration (for reference)
uEnv.txt settings that correctly mux SPI1 pins:
```
enable_uboot_overlays=1
uboot_overlay_addr0=overlays/BB-SPIDEV1-00A0.dtbo
disable_uboot_overlay_emmc=1
disable_uboot_overlay_video=1
disable_uboot_overlay_audio=1
disable_uboot_overlay_wireless=1
disable_uboot_overlay_adc=1
```

## Bug Report Information
If reporting to BeagleBoard:
- **Kernel**: 6.18.6-bone16
- **Driver**: omap2_mcspi
- **Issue**: SPI channel never enables (CH0CTRL EN bit stays 0)
- **Affected**: Any SPI1 usage on BeagleBone with this kernel
- **Regression**: Worked before Jan 22, 2026 kernel update

## Files
- Schematic: beaglewire.pdf (in project)
- Device tree overlay source: ~/Projects/Github/BeagleBoard-DeviceTrees/