#!/bin/bash

##########################################
## Script to prgoram beaglewire with spi
##########################################

echo -e "\n|--------------------------------------------|"
echo -e "|-----Flashing Beaglewire with SPI MODE -----|"
echo -e "|--------------------------------------------|\n\n"

#echo -e "Truncating file to max limit of 4194304\n"
#truncate $1 -s 4194304 
FILE=$1
MAX=4194304
SIZE=$(stat -c%s "$FILE")

if [ "$SIZE" -gt "$MAX" ]; then
    echo "Error: $FILE is too large ($SIZE > $MAX bytes)"
    exit 1
fi

EXIT 0

echo -e "Turning off FPGA by keeping reset High"
gpioset -c gpiochip2 -b pull-up -p 1ms -t 0 21=0
# Run gpioset in background, keep PID
gpioset -c gpiochip2 21=1 &
GPIOSET_PID=$!
gpioget -c gpiochip2 21
#gpioset -c gpiochip2 -p 1ms -t 0 21=1   # pulse high then exit
#gpioset -c gpiochip2 -p 1ms -t 0 21=0   # pulse low then exit
gpioget -c gpiochip2 21
echo -e "Activating SPI mode"
#config-pin P9_28 spi_cs
#config-pin P9_31 spi_sclk

#echo -e "Activating the flash chip with 0xAB command\n"
echo -e "Activating the flash chip; Transmit the byte \xab data\n"
#spi_test -d /dev/spidev1.0 -l 1 -m ab 
sudo ./spidev_test -D /dev/spidev1.0 -s 500000 -p "\xaa"

echo -e "\n|--------------------------------------------|"
echo -e "|---------  Programming nor flash -----------|"
echo -e "|--------------------------------------------|\n"

echo -e "Flashing nor flash with the $1 bin file\n"
flashrom -p linux_spi:dev=/dev/spidev1.0,spispeed=25000000 -w $1 -c MX25L3273E || echo "Failed, Rerun the script"

echo -e "Turning on FPGA by keeping reset Low"
config-pin P9_25 gpio_pd
echo in > /sys/class/gpio/gpio117/direction || echo in > /sys/class/gpio/gpio117/direction

echo -e "Deactivating SPI mode"
config-pin P9_28 gpio
config-pin P9_31 gpio

echo -e "|---------------------------------------------|"
echo -e "|----RESET THE FPGA to run the bitstream -----|"
echo -e "|---------------------------------------------|"
