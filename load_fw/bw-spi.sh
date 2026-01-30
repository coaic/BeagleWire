#!/bin/bash
##########################################
## Script to program BeagleWire SPI flash
## Updated for Debian Trixie (2024+)
## 
## Uses modern tools:
##   - gpioset (libgpiod) instead of sysfs gpio
##   - flashrom for SPI flash programming
##
## The flow:
##   1. Hold FPGA in reset (CRESET low) so it releases the SPI bus
##   2. Program the SPI flash using flashrom
##   3. Release FPGA reset so it boots from flash
##########################################

set -e

# Configuration
BITSTREAM="$1"
SPI_DEV="/dev/spidev1.0"
SPI_SPEED="10000000"  # 10 MHz (conservative, can try 25000000)
FLASH_CHIP="MX25L3273E"  # Or use "W25Q32.V" or let flashrom auto-detect

# GPIO configuration for BeagleWire
# P9_25 = GPIO3_21 = (3*32)+21 = 117 in legacy numbering
# In libgpiod: gpiochip2, line 21 (because gpiochip0=gpio0, gpiochip1=gpio1, etc.)
# BUT on AM335x, the mapping might be different - let's use gpiochip3 line 21
# Actually from your earlier output: gpiochip2 line 21 = P9_25
GPIO_CHIP="2"
CRESET_LINE="21"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check arguments
if [ -z "$BITSTREAM" ]; then
    echo "Usage: $0 <bitstream.bin>"
    echo ""
    echo "Programs the BeagleWire SPI flash with the given bitstream."
    echo "After programming, press the RESET button on BeagleWire to boot the FPGA."
    exit 1
fi

if [ ! -f "$BITSTREAM" ]; then
    echo_err "Bitstream file not found: $BITSTREAM"
    exit 1
fi

# Check for required tools
check_tool() {
    if ! command -v "$1" &> /dev/null; then
        echo_err "$1 is not installed. Install with: sudo apt install $2"
        exit 1
    fi
}

check_tool gpioset gpiod
check_tool flashrom flashrom

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo_err "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo "|--------------------------------------------|"
echo "|---- Flashing BeagleWire with SPI MODE ----|"
echo "|--------------------------------------------|"
echo ""

# Get file size
FILESIZE=$(stat -c%s "$BITSTREAM")
echo_info "Bitstream file: $BITSTREAM ($FILESIZE bytes)"

# Truncate/pad to flash size if needed (4MB = 4194304 bytes)
# Actually, let's NOT truncate - flashrom handles this better
# The original script truncated to exactly 4MB which could corrupt the bitstream
# if it was smaller, or fail if larger

if [ "$FILESIZE" -gt 4194304 ]; then
    echo_err "Bitstream too large for 4MB flash ($FILESIZE > 4194304)"
    exit 1
fi

echo_info "Step 1: Holding FPGA in reset (CRESET low)"
# Kill any existing gpioset processes that might be holding the line
pkill -f "gpioset.*$GPIO_CHIP.*$CRESET_LINE" 2>/dev/null || true
sleep 0.1

# Assert CRESET low (active low reset)
# Using -z (daemonize) to keep the line held
# The line is active-low, so we set it to 0 to assert reset
gpioset -z -c "$GPIO_CHIP" "$CRESET_LINE"=0 &
GPIOSET_PID=$!
sleep 0.2

# Verify GPIO is set
echo_info "  CRESET held low (PID: $GPIOSET_PID)"

echo_info "Step 2: Waking up SPI flash"
# Send Release from Deep Power-Down command (0xAB)
# This wakes the flash if it was in low-power mode
# Using spidev_test or a simple python script

# Try with spidev_test if available, otherwise use python
if command -v spidev_test &> /dev/null; then
    spidev_test -D "$SPI_DEV" -s 1000000 -p "\xAB" > /dev/null 2>&1 || true
else
    # Use python as fallback
    python3 -c "
import spidev
spi = spidev.SpiDev()
spi.open(1, 0)
spi.max_speed_hz = 1000000
spi.xfer([0xAB])
spi.close()
" 2>/dev/null || echo_warn "Could not send wake command (continuing anyway)"
fi
sleep 0.1

echo_info "Step 3: Programming SPI flash with flashrom"
echo ""

# Run flashrom
# -p linux_spi: use Linux SPI device
# -c: specify chip (or remove to auto-detect)
# -w: write
# -n: don't verify (faster, remove for verification)

FLASHROM_OPTS="-p linux_spi:dev=$SPI_DEV,spispeed=$SPI_SPEED"

# Try to auto-detect chip first
echo_info "  Detecting flash chip..."
DETECTED_CHIP=$(flashrom $FLASHROM_OPTS 2>&1 | grep -oP '"\K[^"]+(?=" found)' | head -1) || true

if [ -n "$DETECTED_CHIP" ]; then
    echo_info "  Detected: $DETECTED_CHIP"
    FLASH_CHIP="$DETECTED_CHIP"
fi

echo_info "  Writing bitstream to flash..."
if flashrom $FLASHROM_OPTS -c "$FLASH_CHIP" -w "$BITSTREAM"; then
    echo ""
    echo_info "Flash programming successful!"
else
    echo ""
    echo_err "Flash programming failed!"
    echo_warn "Try running with different chip: -c W25Q32.V or -c MX25L3233F"
    
    # Cleanup
    kill $GPIOSET_PID 2>/dev/null || true
    exit 1
fi

echo ""
echo_info "Step 4: Releasing FPGA reset"

# Kill the gpioset process to release the GPIO
kill $GPIOSET_PID 2>/dev/null || true
sleep 0.1

# Set CRESET high to release reset (FPGA will boot from flash)
# Quick pulse - just release it
gpioset -c "$GPIO_CHIP" "$CRESET_LINE"=1
sleep 0.1

# Now let it float (tri-state) by not driving it
# The pull-up on the board should keep it high

echo ""
echo "|---------------------------------------------|"
echo "|            Programming Complete!            |"
echo "|---------------------------------------------|"
echo ""
echo "The FPGA should now boot from flash automatically."
echo "If not, press the RESET button on the BeagleWire."
echo ""
