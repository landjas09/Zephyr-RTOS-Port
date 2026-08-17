# Zephyr RTOS Port — ESP32-C3 IoT Sensor Node

Zephyr board support for the custom ESP32-C3 IoT Sensor Node hardware, developed against **Zephyr 4.2.0-rc1** and targeting the **ESP32-C3-WROOM-02-H4** module.

This document covers the software port only. Hardware design and PCB documentation live in the (https://github.com/landjas09/Custom-IoT-development-board-ESP32-C3/blob/main/README.md)

---

## Contents

1. [Overview](#1-overview)
2. [Target Hardware](#2-target-hardware)
3. [Board Directory Structure](#3-board-directory-structure)
4. [Kconfig Architecture](#4-kconfig-architecture)
5. [Devicetree Architecture](#5-devicetree-architecture)
6. [Debugging / OpenOCD](#6-debugging--openocd)
7. [Prerequisites](#7-prerequisites)
8. [Building Applications](#8-building-applications)
9. [Problems Encountered & Resolutions](#9-problems-encountered--resolutions)
10. [Current Status](#10-current-status)
11. [References](#11-references)

---

## 1. Overview

The board was originally developed on Arduino/ESP-IDF, which is a reasonable starting point for early hardware bring-up but starts to show real limits once a project grows past a single sketch-style `loop()`. This board runs several genuinely concurrent responsibilities — polling I²C sensors, streaming analog samples from the microphone, servicing SPI transfers to the SD card and flash chip, and handling UART/USB communication — and coordinating all of that correctly on bare ESP-IDF means hand-rolling scheduling, synchronization, and timing logic that a proper RTOS already provides as first-class primitives (threads, mutexes, semaphores, message queues, work queues).

Zephyr also decouples the *hardware description* from the *application logic* in a way ESP-IDF/Arduino don't: peripherals, pin assignments, and bus topology live in Devicetree and Kconfig rather than being wired directly into application code. That means the same firmware can target a different board revision, or even a different MCU family entirely, by swapping the board definition rather than rewriting driver calls throughout the application — which matters here specifically, since this board has already gone through more than one hardware revision.

There's also a practical, career-facing reason for the choice: Zephyr is the RTOS underpinning a large share of real production IoT and embedded products (Nordic's nRF Connect SDK, many NXP and ST parts), backed by the Linux Foundation with long-term support releases, an active driver ecosystem, and a genuine upstream contribution model. Porting a custom board to it — including working through the board-definition, Devicetree, and Kconfig layers by hand rather than using a vendor-provided starting point — is a closer approximation of how embedded firmware is actually structured in industry than an Arduino sketch, and was worth the added complexity for that reason alone.

The port adds `iot_sensor_node_esp32c3` as a native Zephyr board target, exposing the board's peripherals through Devicetree and Kconfig so that standard Zephyr applications can be built against the hardware without board-specific application code.

```
Existing Zephyr ESP32-C3 SoC support
        │
        ▼
Custom board Devicetree
        │
        ├── BME280 (I²C)
        ├── OLED connector (I²C)
        ├── W25Q32 flash (SPI)
        ├── SD card (SPI)
        ├── CP2102N UART bridge
        ├── ADC-connected analog sensors
        └── GPIO / buttons / USB-JTAG breakout
```

Reference starting point: the existing **ESP32-C3-DevKitC** board support included in Zephyr was adapted rather than copied — Devicetree, pinctrl, Kconfig, build, and debug configuration were each modified to match the custom hardware.

---

## 2. Target Hardware

| Subsystem | Component | Interface |
|---|---|---|
| MCU | ESP32-C3-WROOM-02-H4 | — |
| Temperature / Humidity / Pressure | BME280 | I²C |
| Ambient Light | TEMT6000X01 | ADC |
| Microphone | CMC-5042PF-AC + MAX4466EXK | ADC |
| External Flash | W25Q32JVSSIQ | SPI |
| SD Card | GSD090012SEU | SPI |
| USB-UART Bridge | CP2102N-Axx-xQFN20 | UART |
| Display Expansion | OLED connector | I²C |
| Debugging | ESP32-C3 native USB/JTAG | GPIO18 / GPIO19 |
| User Input | BOOT / EN buttons | GPIO |

---

## 3. Board Directory Structure

```
zephyr/boards/others/iot_sensor_node_esp32c3/
│
├── board.cmake
├── iot_sensor_node_esp32c3.yaml
├── iot_sensor_node_esp32c3.dts
├── iot_sensor_node_esp32c3-pinctrl.dtsi
│
├── Kconfig
├── Kconfig.board
├── Kconfig.defconfig
├── Kconfig.sysbuild
│
├── support/
│   └── openocd.cfg
│
└── doc/
    └── index.rst
```

| Category | Files |
|---|---|
| Board metadata | `iot_sensor_node_esp32c3.yaml` |
| Build / runner integration | `board.cmake` |
| Kconfig | `Kconfig`, `Kconfig.board`, `Kconfig.defconfig`, `Kconfig.sysbuild` |
| Hardware description | `iot_sensor_node_esp32c3.dts`, `iot_sensor_node_esp32c3-pinctrl.dtsi` |
| Debugging | `support/openocd.cfg` |
| Documentation | `doc/index.rst` |

No board-specific `CMakeLists.txt` is required — the board relies entirely on Zephyr's existing ESP32 board infrastructure.

### Board Metadata

`iot_sensor_node_esp32c3.yaml` identifies the board to Zephyr's tooling:

```yaml
identifier: iot_sensor_node_esp32c3
name: ESP32-C3
type: mcu
arch: riscv
toolchain:
  - zephyr
vendor: espressif
supported:
  - adc
  - gpio
  - i2c
  - watchdog
  - uart
  - dma
  - pwm
  - spi
  - counter
  - entropy
```

### Build Integration

`board.cmake` reuses Zephyr's common ESP32 and OpenOCD runner infrastructure rather than implementing custom flashing logic:

```cmake
include(${ZEPHYR_BASE}/boards/common/esp32.board.cmake)
include(${ZEPHYR_BASE}/boards/common/openocd.board.cmake)
```

---

## 4. Kconfig Architecture

| File | Responsibility |
|---|---|
| `Kconfig` | Board Kconfig entry point — exposes board-specific symbols to the configuration system |
| `Kconfig.board` | Identifies the board and selects the underlying ESP32-C3 SoC configuration |
| `Kconfig.defconfig` | Board-specific default configuration (console, serial, GPIO) |
| `Kconfig.sysbuild` | Sysbuild / MCUboot defaults |

`Kconfig.board` selects the existing Zephyr ESP32-C3-WROOM SoC support rather than introducing a new SoC implementation:

```kconfig
config BOARD_IOT_SENSOR_NODE_ESP32C3
    select SOC_ESP32C3_WROOM_02_N4
```

`Kconfig.sysbuild` configures the board to participate in Sysbuild with MCUboot:

```kconfig
choice BOOTLOADER
    default BOOTLOADER_MCUBOOT
endchoice

choice BOOT_SIGNATURE_TYPE
    default BOOT_SIGNATURE_TYPE_NONE
endchoice
```

### Board Heap Configuration

The ESP32-C3 Espressif HAL uses Zephyr's dynamic kernel allocator for components including SPI flash handling and interrupt allocation. Without additional heap headroom, linking failed with unresolved references to `k_malloc`, originating from those HAL components.

The board therefore provides additional kernel heap through `Kconfig.defconfig`:

```kconfig
config HEAP_MEM_POOL_ADD_SIZE_BOARD
    int
    default 4096
```

This is board-level configuration rather than application-level, since the requirement originates from the ESP32-C3 HAL/board integration itself. Applications with larger dynamic-memory needs can still extend the heap through their own configuration.

---

## 5. Devicetree Architecture

The hardware description is split across two files:

- **`iot_sensor_node_esp32c3.dts`** — board-level hardware description
- **`iot_sensor_node_esp32c3-pinctrl.dtsi`** — pin multiplexing, kept separate to isolate GPIO-matrix configuration from peripheral definitions

### GPIO Assignment

| Function | GPIO | Interface | Notes |
|---|---:|---|---|
| I²C SDA | GPIO4 | I²C | BME280 + OLED connector |
| I²C SCL | GPIO3 | I²C | BME280 + OLED connector |
| SPI SCLK | GPIO6 | SPI | Shared bus |
| SPI MOSI | GPIO7 | SPI | Shared bus |
| SPI MISO | GPIO2 | SPI | Shared bus |
| W25Q32 CS | GPIO10 | SPI | Dedicated chip select |
| SD Card CS | GPIO5 | SPI | Dedicated chip select |
| UART TX | GPIO21 | UART | CP2102N RXD |
| UART RX | GPIO20 | UART | CP2102N TXD |
| USB D− | GPIO18 | USB / JTAG | Exposed as breakout |
| USB D+ | GPIO19 | USB / JTAG | Exposed as breakout |

### I²C

SDA/SCL are shared across the bus's peripherals, with external pull-ups provided by the hardware design.

- **BME280** — `compatible = "bosch,bme280";` — exposed through Zephyr's standard sensor API (temperature, pressure, humidity)
- **OLED connector** — shares the same bus; kept generic in the base board definition rather than binding a specific display driver, so different compatible I²C displays can be attached and configured through an application overlay

### SPI

W25Q32 and the SD card share SCLK/MOSI/MISO with independent chip-select lines:

```
                ┌── W25Q32 (SPI NOR)      CS → GPIO10
ESP32-C3 SPI ───┤
                └── SD Card               CS → GPIO5
```

- **W25Q32** — `compatible = "jedec,spi-nor";`. The node includes explicit JEDEC ID and flash-size properties, required when runtime SFDP discovery is not enabled.
- **SD Card** — `compatible = "zephyr,sdhc-spi-slot";` at 20 MHz, exposing storage through `compatible = "zephyr,sdmmc-disk";` so applications access it via Zephyr's storage subsystem rather than driving SPI directly.

### ADC

The ADC controller is inherited from the ESP32-C3 SoC definition (`compatible = "espressif,esp32-adc";`) and enabled at board level. Analog peripherals (microphone amplifier output, ambient light sensor) are connected via Zephyr's `io-channels` mechanism, exposing them through the standard Zephyr ADC API rather than direct register access.

### UART

CP2102N ↔ ESP32-C3, using the SoC's inherited UART driver:

```
CP2102N TXD ──────────────▶ GPIO20 (ESP32-C3 RX)
CP2102N RXD ◀────────────── GPIO21 (ESP32-C3 TX)
```

Serves as the board's primary console/log/serial interface.

### Buttons

**BOOT** is a genuine GPIO (GPIO9) and is represented as a GPIO node in the board Devicetree, making it accessible through Zephyr's standard GPIO API when an application needs software-visible access to it.

**EN** is the ESP32-C3's dedicated hardware enable/reset pin — it sits outside the GPIO matrix entirely and is not a GPIO in any capacity. It cannot be represented as a Devicetree GPIO node; it is purely a hardware-level reset control, not a software-visible resource.

### USB / JTAG — Design Decision

GPIO18/GPIO19 carry the ESP32-C3's native USB D−/D+ signals, which double as its built-in USB/JTAG debug interface. Rather than permanently reserving these pins for debugging, they are exposed as general breakout pins in the base board definition. USB/JTAG functionality is enabled on demand through the OpenOCD configuration and, where needed, a Devicetree overlay — leaving the pins available for other application use whenever debugging isn't active.

### Devicetree Overlays

The base `.dts` describes the board's default hardware configuration; application-specific needs (alternate use of GPIO18/19, additional peripherals, display selection) are handled through overlays rather than modifying the board definition itself — allowing one board port to serve multiple applications cleanly.

---

## 6. Debugging / OpenOCD

`support/openocd.cfg` supports two debug paths:

```tcl
set ESP_RTOS none

# ESP32-C3 built-in USB/JTAG over GPIO18/GPIO19 (D-/D+)
# source [find interface/esp_usb_jtag.cfg]

# External ESP-Prog JTAG (default)
source [find interface/ftdi/esp32_devkitj_v1.cfg]
source [find target/esp32c3.cfg]
adapter speed 5000
```

External ESP-Prog is enabled by default; the native USB/JTAG path can be swapped in by uncommenting the corresponding interface line. OpenOCD itself is located via the Espressif toolchain path through `board.cmake`.

---

## 7. Prerequisites

To build against this board, a working Zephyr workspace is required:

- **Zephyr SDK** matching the Zephyr 4.2.0-rc1 toolchain requirements
- **`west`** (Zephyr's meta-tool) and a Python environment with Zephyr's `requirements.txt` installed
- **Espressif toolchain** (provides `openocd`, used by `board.cmake`'s OpenOCD path lookup)

### Adding the board to a workspace

This board directory is not part of upstream Zephyr, so it needs to be made visible to the build system in one of two ways:

**Option A — custom board root (recommended, no upstream files touched):**
```bash
west build -b iot_sensor_node_esp32c3 samples/hello_world \
    -- -DBOARD_ROOT=<path-to-this-repo>/zephyr
```
This assumes the board directory lives at `<repo>/zephyr/boards/others/iot_sensor_node_esp32c3/` as shown in [Section 3](#3-board-directory-structure).

**Option B — copy into the Zephyr tree:**
Place `boards/others/iot_sensor_node_esp32c3/` directly under your local `zephyr/boards/others/` directory. Simpler for a one-off build, but the board definition then lives outside version control for your Zephyr checkout.

---

## 8. Building Applications

The board is selected by its identifier:

```bash
west build -b iot_sensor_node_esp32c3 samples/hello_world
```

Use a pristine build after changing board-level Devicetree, pinctrl, or Kconfig:

```bash
west build -b iot_sensor_node_esp32c3 samples/hello_world -p always
```

### Application Overlay

Board-level hardware description stays fixed; application-specific needs are layered in via an overlay:

```
app/
├── CMakeLists.txt
├── prj.conf
├── src/
│   └── main.c
└── boards/
    └── iot_sensor_node_esp32c3.overlay
```

### Application Configuration

Zephyr subsystems needed by a given application are enabled in `prj.conf`, not the board files:

```conf
CONFIG_GPIO=y
CONFIG_I2C=y
CONFIG_SPI=y
CONFIG_SENSOR=y
```

This keeps the board definition (hardware description) cleanly separated from application requirements (software feature selection), so the same port supports multiple applications without modification.

---

## 9. Problems Encountered & Resolutions

| Problem | Cause | Resolution |
|---|---|---|
| `undefined reference to 'k_malloc'` at link time | Missing board-level heap allocation for ESP32-C3 HAL components (SPI flash handling, interrupt allocation) | Added `HEAP_MEM_POOL_ADD_SIZE_BOARD` (4096 bytes) to board Kconfig |
| `'reg' property ... has length 4, which is not evenly divisible by 12` | Inherited ADC Devicetree node used a `reg` property with the wrong cell count for the ESP32-C3's 2 address-cell / 1 size-cell configuration | Corrected the ADC node's `reg` property to match the parent's address/size-cell layout |
| `jedec,spi-nor jedec-id required for non-runtime SFDP` / `size required for non-runtime SFDP page layout` | W25Q32 Devicetree node was missing required JEDEC ID and flash-size properties | Added the required properties to the SPI NOR node |
| SD card not represented correctly | Missing/incorrect `zephyr,sdhc-spi-slot` binding structure | Added the correct SDHC SPI slot node with a nested `zephyr,sdmmc-disk` child |

Each issue was resolved at the board-definition level, so application code targeting this board doesn't need to work around any of them.

---

## 10. Current Status

| Area | Status |
|---|---|
| Board definition, metadata, build integration | Complete |
| Devicetree | Complete |
| Pin control | Complete |
| Kconfig (board defaults, heap, sysbuild) | Complete |
| GPIO | Implemented |
| ADC | Implemented |
| I²C / BME280 | Implemented |
| SPI / SPI NOR (W25Q32) | Implemented |
| SD card | Implemented |
| UART (CP2102N) | Implemented |
| USB / JTAG configuration | Implemented |
| OpenOCD integration | Implemented |

Validated through Zephyr's full build pipeline (Devicetree generation → Kconfig processing → compilation → linking → ESP32-C3 image generation), and confirmed by building relevant Zephyr samples against each subsystem above.

**Not yet implemented:** DS3231 RTC (planned — will be added to this port once integrated into the hardware design).

---

## 11. References

**Zephyr** — Project documentation, board porting guide, Devicetree documentation, Kconfig documentation, device driver documentation, ESP32 board support.

**Espressif** — ESP32-C3 documentation, ESP32-C3-WROOM-02 datasheet, ESP32-C3 Technical Reference Manual, Espressif HAL, Espressif OpenOCD.

**Component datasheets** — ESP32-C3-WROOM-02-H4, BME280, W25Q32JV, CP2102N, MCP73871, LM1117, MAX4466, TEMT6000, SD card interface specification.

**Reference implementation** — Zephyr's built-in ESP32-C3-DevKitC board support, used as the adaptation baseline for this port.
