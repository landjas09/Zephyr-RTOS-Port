.. zephyr:board:: iot_sensor_node_esp32c3


Overview

---

The ESP32-C3 IoT Sensor Node is a custom development board based on the
ESP32-C3-WROOM-02-H4 module. The board is designed as a general-purpose
IoT and embedded development platform with integrated sensing, storage,
USB-UART connectivity, and expansion interfaces.

The board provides interfaces for I2C and SPI sensors, analog sensors,
external SPI flash, an SD card, and an optional OLED display through a
breakout connector.

The board is supported by Zephyr RTOS through a custom board definition
and Devicetree configuration.

Hardware

---

The board is based on the Espressif ESP32-C3-WROOM-02-H4 module.

# Main hardware components

* ESP32-C3-WROOM-02-H4
* MCP73871 Li-Po battery charger
* LM1117-3.3 voltage regulator
* CP2102N USB-UART bridge
* BME280 temperature, pressure, and humidity sensor
* TEMT6000 ambient light sensor
* MAX4466 microphone amplifier
* W25Q32JV SPI NOR flash
* MicroSD card interface
* USB-C connector
* BOOT and EN buttons
* OLED expansion connector
* GPIO expansion headers

# Hardware interfaces

## I2C

* SDA: GPIO4
* SCL: GPIO3
* BME280 at address 0x76
* OLED expansion interface

## SPI

SPI2 is used for the external SPI peripherals:

* MISO: GPIO2
* SCLK: GPIO6
* MOSI: GPIO7
* W25Q32 chip select: GPIO10
* SD card chip select: GPIO5

## ADC

The board provides two analog inputs:

* ADC channel 0 / GPIO0: MAX4466 microphone output
* ADC channel 1 / GPIO1: TEMT6000 ambient-light sensor

## UART

UART0 is connected to the external CP2102N USB-UART bridge:

* TX: GPIO21
* RX: GPIO20
* Baud rate: 115200

## User input

* BOOT button: GPIO9
* EN button: ESP32-C3 reset input

## Expansion GPIOs

The following GPIOs are exposed through the breakout interface:

* GPIO8
* GPIO18
* GPIO19

GPIO18 and GPIO19 are not permanently assigned to JTAG in the base
Devicetree. They remain available as expansion GPIOs and can be configured
for other peripherals through a Devicetree overlay.

# Supported Features

.. zephyr:board-supported-hw::

System requirements

---

# Prerequisites

The Espressif HAL may require Wi-Fi and Bluetooth binary blobs for
applications using those features. The required blobs can be retrieved
with:

.. code-block:: console

west blobs fetch hal_espressif

It is recommended to run this command after `west update`.

Building & Flashing
********************

.. zephyr:board-supported-runners::

Simple boot
===========

The board can be loaded using a single application image without the
MCUboot second-stage bootloader.

This is the default configuration when building an application without
enabling MCUboot.

.. note::

   Simple boot does not provide the security and firmware-update features
   provided by MCUboot.

MCUboot bootloader
==================

MCUboot can be used when the application requires a bootloader for
firmware image validation, secure firmware updates, or OTA update
workflows.

The bootloader must be built and flashed together with the application
when MCUboot is enabled.

MCUboot can be enabled with:

.. code-block:: cfg

   CONFIG_BOOTLOADER_MCUBOOT=y

There are two ways to build an application with MCUboot:

1. Sysbuild
2. Manual build

Sysbuild
========

Sysbuild can be used to build the application and MCUboot together.

Build the Hello World sample using:

.. zephyr-app-commands::
   :tool: west
   :zephyr-app: samples/hello_world
   :board: iot_sensor_node_esp32c3
   :goals: build
   :west-args: --sysbuild
   :compact:

The resulting build directory contains separate build domains for the
application and MCUboot:

.. code-block::

   build/
   ├── hello_world
   │   └── zephyr
   │       ├── zephyr.elf
   │       └── zephyr.bin
   ├── mcuboot
   │   └── zephyr
   │       ├── zephyr.elf
   │       └── zephyr.bin
   └── domains.yaml

With the ``--sysbuild`` option, MCUboot and the application are managed
as separate build domains.

Manual build
============

During development, the application and MCUboot can also be built
separately.

Build the application normally:

.. zephyr-app-commands::
   :zephyr-app: samples/hello_world
   :board: iot_sensor_node_esp32c3
   :goals: build

The usual ``flash`` target can be used when a supported flashing
interface is connected:

.. zephyr-app-commands::
   :zephyr-app: samples/hello_world
   :board: iot_sensor_node_esp32c3
   :goals: flash

When using MCUboot, the bootloader must be flashed before the application
image can be booted through MCUboot.

Serial monitor
==============

The ESP32 console can be monitored using:

.. code-block:: console

   west espressif monitor

After the board boots, Zephyr messages are displayed through the UART
console connected to the CP2102N USB-UART bridge.

Debugging

---

The ESP32-C3 provides a built-in USB-JTAG interface through GPIO18 (USB D-)
and GPIO19 (USB D+).

On this board, GPIO18 and GPIO19 are exposed through the breakout interface
and are not permanently reserved for JTAG in the base Devicetree. This
allows users to configure these pins for other peripherals when JTAG
debugging is not required.

When USB-JTAG debugging is required, the corresponding GPIO configuration
can be provided through a Devicetree overlay.

The board also provides an OpenOCD configuration in:

.. code-block:: text

support/openocd.cfg

The board's OpenOCD configuration can be used with the standard Zephyr
debug infrastructure.

To start a debug session:

.. zephyr-app-commands::
:zephyr-app: samples/hello_world
:board: iot_sensor_node_esp32c3
:goals: debug

Supported runners can be displayed automatically with:

.. zephyr:board-supported-runners::

Hardware validation

---

The board configuration has been validated through Zephyr build and
Devicetree checks.

The following hardware interfaces have been represented and build-tested:

* GPIO and BOOT button
* UART0 console
* I2C0 with BME280
* SPI2 with W25Q32 SPI NOR flash
* SPI2 with SD card
* ADC channel 0 for the MAX4466 microphone amplifier
* ADC channel 1 for the TEMT6000 ambient-light sensor

Physical hardware validation:

The following operationshave  been electricallyn verified on the physical board:

* Sensor measurements
* SD card read/write operation
* SPI NOR flash read/write operation
* CP2102N UART communication
* BOOT button operation
* ADC measurements
* JTAG debugging
* USB-JTAG operation

References

---

For detailed electrical specifications and peripheral information, refer
to the following Espressif documentation:

* ESP32-C3 Datasheet
* ESP32-C3 Technical Reference Manual
* ESP32-C3-WROOM-02 Datasheet

The board's Zephyr implementation is based on the ESP32-C3 SoC support
provided by the Espressif HAL.
