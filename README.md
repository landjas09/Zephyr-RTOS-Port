# Zephyr RTOS Port — ESP32-C3 Secure-Ready Battery-Powered Edge Logger

Zephyr board support for the custom **ESP32-C3 Secure-Ready Battery-Powered Edge Logger**, developed against **Zephyr 4.2.0-rc1** and targeting the **ESP32-C3-WROOM-02-H4** module.

This port is the Rev 2 evolution of the original ESP32-C3 IoT Sensor Node support. The original sensing, storage, UART, ADC, SPI, GPIO, and USB/JTAG configuration is retained, while the board Devicetree is extended for the **DS3231SN battery-backed RTC**, **BQ27441-G1A fuel gauge**, and **NXP EdgeLock SE050E2 secure-element transport**.

This document covers the software port only. Hardware design and PCB documentation live in the [hardware repository](https://github.com/landjas09/Custom-IoT-development-board-ESP32-C3/tree/main/hardware/rev2_secure-edge-logger).

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
12. [Revision History](#12-revision-history)

---

## 1. Overview

The original port moved the custom ESP32-C3 board into Zephyr's board-support model so hardware description, pin assignment, buses, and board defaults are kept outside application code. Rev 1 already exposed the board's core sensing, storage, ADC, SPI, UART, GPIO, and debug resources through standard Zephyr mechanisms.

Hardware Rev 2 evolves the board from a general-purpose IoT development board into a **Secure-Ready Battery-Powered Edge Logger**. The Zephyr port therefore extends the existing board definition around three new hardware functions:

- **DS3231SN** — persistent battery-backed absolute timekeeping for timestamped logging
- **BQ27441-G1A** — battery fuel gauging and battery-state observability
- **NXP EdgeLock SE050E2** — secure-element I²C transport for NXP Plug & Trust middleware

The existing Rev 1 support remains in place:

- BME280 environmental sensor over I²C
- TEMT6000 ambient-light input through ADC
- MAX4466 microphone-amplifier output through ADC
- W25Q32 SPI NOR flash
- microSD storage over SPI
- CP2102N UART console/programming path
- BOOT GPIO
- native ESP32-C3 USB/JTAG capability on GPIO18/GPIO19

The port adds `iot_sensor_node_esp32c3` as a native Zephyr board target, exposing the board's peripherals through Devicetree and Kconfig so standard Zephyr applications can be built against the custom hardware without hard-coding board-specific peripheral details into application source.

```text
Existing Zephyr ESP32-C3 SoC support
        │
        ▼
Custom board Devicetree
        │
        ├── BME280 (I²C)
        ├── DS3231SN RTC (I²C)
        ├── BQ27441-G1A fuel gauge (I²C)
        ├── SE050E2 transport (I²C / Plug & Trust)
        ├── OLED connector (I²C)
        ├── W25Q32 flash (SPI)
        ├── SD card (SPI)
        ├── CP2102N UART bridge
        ├── ADC-connected analog sensors
        ├── BOOT GPIO
        └── GPIO18/GPIO19 USB-JTAG breakout
```

Reference starting point: the existing **ESP32-C3-DevKitC** board support included in Zephyr was adapted rather than copied blindly. Devicetree, pinctrl, Kconfig, build integration, heap configuration, storage nodes, and debug configuration were modified to match the custom hardware.

### Rev 1 → Rev 2 software evolution

The Rev 2 transition required only limited board-support changes because the original architecture already used a shared I²C bus and standard Zephyr peripheral descriptions.

The main Rev 2 changes are:

- added the modern **DS3231 MFD + RTC child-node** structure
- assigned **GPIO8** to DS3231 `INT/SQW`
- added **BQ27441-G1A** at I²C address `0x55`
- added `se05x-i2c = &i2c0;` for NXP Plug & Trust transport
- retained the existing BME280, OLED header, SPI, ADC, UART, BOOT, and USB/JTAG configuration

The **TPS63802 buck-boost regulator** does not require a Zephyr node in the current design because enable/mode behavior is hardware-strapped and its power-good output is not connected to the MCU.

---

## 2. Target Hardware

| Subsystem | Component | Interface |
|---|---|---|
| MCU | ESP32-C3-WROOM-02-H4 | — |
| Temperature / Humidity / Pressure | BME280 | I²C |
| Real-Time Clock | DS3231SN | I²C + GPIO8 `INT/SQW` |
| Battery Fuel Gauge | BQ27441-G1A | I²C |
| Secure Element | NXP EdgeLock SE050E2 | I²C via NXP Plug & Trust |
| Display Expansion | OLED connector | I²C |
| Ambient Light | TEMT6000X01 | ADC |
| Microphone | CMC-5042PF-AC + MAX4466EXK | ADC |
| External Flash | W25Q32JVSSIQ | SPI |
| SD Card | GSD090012SEU | SPI |
| USB-UART Bridge | CP2102N-Axx-xQFN20 | UART |
| Debugging | ESP32-C3 native USB/JTAG | GPIO18 / GPIO19 |
| User Input | BOOT / EN buttons | GPIO / hardware reset |
| 3.3 V Regulation | TPS63802 | Hardware-managed; no current Zephyr node |

The Rev 2 I²C peripherals share the same physical bus:

```text
ESP32-C3 I²C0
    SDA → GPIO4
    SCL → GPIO3
        │
        ├── BME280
        ├── OLED header
        ├── DS3231SN
        ├── BQ27441-G1A
        └── SE050E2
```

The base board configuration currently uses **I²C standard mode (100 kHz)**.

---

## 3. Board Directory Structure

```text
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

No board-specific `CMakeLists.txt` is required — the board reuses Zephyr's existing ESP32 board infrastructure.

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

The vendor remains `espressif` because the custom PCB uses Espressif's ESP32-C3 SoC/platform support.

### Build Integration

`board.cmake` reuses Zephyr's common ESP32 and OpenOCD runner infrastructure:

```cmake
include(${ZEPHYR_BASE}/boards/common/esp32.board.cmake)
include(${ZEPHYR_BASE}/boards/common/openocd.board.cmake)
```

---

## 4. Kconfig Architecture

| File | Responsibility |
|---|---|
| `Kconfig` | Board-specific Kconfig options, including additional heap required by the ESP32-C3 HAL integration |
| `Kconfig.board` | Identifies the board and selects the underlying ESP32-C3 SoC configuration |
| `Kconfig.defconfig` | Board defaults for console, serial, UART console, and GPIO |
| `Kconfig.sysbuild` | Sysbuild / MCUboot defaults |

`Kconfig.board` selects the existing ESP32-C3-WROOM SoC support rather than introducing a new SoC implementation:

```kconfig
config BOARD_IOT_SENSOR_NODE_ESP32C3
    select SOC_ESP32C3_WROOM_02_N4
```

`Kconfig.defconfig` supplies the board's baseline defaults:

```kconfig
CONFIG_CONSOLE=y
CONFIG_SERIAL=y
CONFIG_UART_CONSOLE=y
CONFIG_GPIO=y
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

MCUboot support here is separate from the SE050 secure element. The board should not be described as having secure boot merely because the secure element is fitted.

### Board Heap Configuration

During the original port, linking failed with unresolved references to `k_malloc` from Espressif HAL components used for functions including SPI flash handling and interrupt allocation.

The board therefore adds heap headroom in `Kconfig`:

```kconfig
config HEAP_MEM_POOL_ADD_SIZE_BOARD
    int
    default 4096
```

This is an existing board-integration requirement rather than a Rev 2-specific change. The RTC, fuel-gauge, and SE050 transport additions did not require changing it.

---

## 5. Devicetree Architecture

The hardware description is split across two files:

- **`iot_sensor_node_esp32c3.dts`** — board-level hardware description and peripheral topology
- **`iot_sensor_node_esp32c3-pinctrl.dtsi`** — ESP32-C3 pin multiplexing / GPIO-matrix configuration

Rev 2 primarily extends the board `.dts`; the existing UART, I²C, and SPI pinctrl assignments remain valid.

### GPIO Assignment

| Function | GPIO | Interface | Notes |
|---|---:|---|---|
| Microphone ADC | GPIO0 | ADC | MAX4466 output |
| Ambient Light ADC | GPIO1 | ADC | TEMT6000 output |
| SPI MISO | GPIO2 | SPI | Shared bus |
| I²C SCL | GPIO3 | I²C | Shared Rev 2 I²C bus |
| I²C SDA | GPIO4 | I²C | Shared Rev 2 I²C bus |
| SD Card CS | GPIO5 | SPI | Dedicated chip select |
| SPI SCLK | GPIO6 | SPI | Shared bus |
| SPI MOSI | GPIO7 | SPI | Shared bus |
| RTC `INT/SQW` | GPIO8 | GPIO | DS3231 alarm / square-wave output |
| BOOT | GPIO9 | GPIO | Active-low BOOT input |
| W25Q32 CS | GPIO10 | SPI | Dedicated chip select |
| USB D− | GPIO18 | USB / JTAG | Exposed as breakout |
| USB D+ | GPIO19 | USB / JTAG | Exposed as breakout |
| UART RX | GPIO20 | UART | CP2102N TXD |
| UART TX | GPIO21 | UART | CP2102N RXD |

GPIO8 is no longer a spare expansion pin in Rev 2 because it is assigned to the DS3231 `INT/SQW` signal.

### I²C

The Rev 2 bus is enabled on `i2c0`:

```dts
&i2c0 {
    status = "okay";
    clock-frequency = <I2C_BITRATE_STANDARD>;
    pinctrl-0 = <&i2c0_default>;
    pinctrl-names = "default";
};
```

The physical bus uses SDA on GPIO4, SCL on GPIO3, and one shared external pull-up network.

#### BME280

```dts
bme280@76 {
    compatible = "bosch,bme280";
    reg = <0x76>;
};
```

The BME280 is exposed through Zephyr's standard sensor API.

#### OLED connector

The OLED connector remains generic in the base board definition. It shares the I²C bus electrically, but no specific OLED device is forced into the board DTS. A specific display can be added through an application overlay.

#### DS3231SN — MFD + RTC

Zephyr 4.2.0-rc1 provides the modern DS3231 bindings:

- `maxim,ds3231-mfd`
- `maxim,ds3231-rtc`

The chip is represented as an MFD parent with an RTC child:

```dts
ds3231: rtc@68 {
    compatible = "maxim,ds3231-mfd";
    reg = <0x68>;
    status = "okay";

    ds3231_rtc: rtc {
        compatible = "maxim,ds3231-rtc";
        isw-gpios = <&gpio0 8 (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>;
        status = "okay";
    };
};
```

The RTC sample uses the functional RTC child through:

```dts
aliases {
    rtc = &ds3231_rtc;
};
```

This matters because the MFD parent represents the shared DS3231 chip infrastructure, while the child implements Zephyr's RTC API.

#### BQ27441-G1A Fuel Gauge

The fuel gauge uses Zephyr's `ti,bq274xx` binding:

```dts
bq27441: fuel-gauge@55 {
    compatible = "ti,bq274xx";
    reg = <0x55>;
    design-voltage = <3700>;
    design-capacity = <2000>;
    taper-current = <55>;
    terminate-voltage = <3000>;
    zephyr,lazy-load;
    status = "okay";
};
```

Current design parameters:

- I²C address: `0x55`
- nominal battery voltage: `3700 mV`
- design capacity: `2000 mAh`
- taper current: `55 mA`
- terminate voltage: `3000 mV`

The battery capacity and termination values are current design assumptions and can be updated when the final cell is fixed.

No interrupt GPIO is described because BQ27441 `GPOUT` is not connected to the ESP32-C3 in the current hardware.

#### SE050E2 Secure Element

The SE050E2 is **not** represented by an invented native Zephyr `se050@48` node.

Instead, the board exposes the I²C controller used by the secure element to NXP Plug & Trust through:

```dts
aliases {
    se05x-i2c = &i2c0;
};
```

The secure-element protocol stack is supplied by the **NXP Plug & Trust Nano Package** as an external Zephyr module.

```text
Zephyr board DTS
    │
    └── identifies the I²C transport
            │
            ▼
NXP Plug & Trust middleware
            │
            ▼
        SE050E2
```

The presence of the SE050E2 makes the platform **secure-ready**. Key generation, provisioning, signing, authentication, TLS credentials, and other security workflows remain application/middleware responsibilities.

### SPI

W25Q32 and microSD share SCLK/MOSI/MISO with independent chip-select lines:

```text
                ┌── W25Q32 SPI NOR     CS → GPIO10
ESP32-C3 SPI ───┤
                └── microSD            CS → GPIO5
```

- **W25Q32** — `compatible = "jedec,spi-nor";` with explicit JEDEC ID and flash-size properties.
- **microSD** — `compatible = "zephyr,sdhc-spi-slot";` with a nested `compatible = "zephyr,sdmmc-disk";` child.

The current SD SPI frequency is **25 MHz**.

### ADC

The ESP32-C3 ADC controller is inherited from the SoC definition and enabled at board level.

The original port required channel-oriented child addressing:

```dts
&adc0 {
    #address-cells = <1>;
    #size-cells = <0>;
    ...
};
```

This prevents ADC channel child nodes from inheriting the `/soc` address/size-cell format.

The board exposes the MAX4466 microphone output through GPIO0 and the TEMT6000 ambient-light signal through GPIO1 using Zephyr's ADC infrastructure.

### UART

CP2102N ↔ ESP32-C3 uses UART0:

```text
CP2102N TXD ──────────────▶ GPIO20 (ESP32-C3 RX)
CP2102N RXD ◀────────────── GPIO21 (ESP32-C3 TX)
```

This remains the primary serial console/log/programming path.

### Buttons

**BOOT** is connected to GPIO9 and represented as a `gpio-keys` input.

**EN** is the ESP32-C3 hardware enable/reset input. It is outside the GPIO matrix and is not represented as a normal software-visible GPIO node.

### USB / JTAG — Design Decision

GPIO18/GPIO19 carry native USB D−/D+ and the ESP32-C3 built-in USB/JTAG interface.

The base Devicetree leaves them unassigned so they remain available as breakout pins when native USB/JTAG is not in use. When USB/JTAG debugging is active, those pins are occupied by the debug interface.

### Devicetree Overlays

The base `.dts` describes hardware fixed on the PCB. Application-specific choices remain in overlays, such as binding a specific OLED model or assigning external breakout peripherals.

---

## 6. Debugging / OpenOCD

The current `support/openocd.cfg` uses the ESP32-C3 built-in USB/JTAG interface:

```tcl
set ESP_RTOS none
source [find interface/esp_usb_jtag.cfg]
source [find target/esp32c3.cfg]
adapter speed 5000
```

This uses the native USB/JTAG peripheral on GPIO18/GPIO19 and does not require an external FTDI-based ESP-Prog interface.

---

## 7. Prerequisites

To build against this board, a working Zephyr workspace is required:

- **Zephyr 4.2.0-rc1**
- **Zephyr SDK** compatible with the selected Zephyr version
- **`west`** and Zephyr's Python dependencies
- **Espressif toolchain / OpenOCD** for ESP32-C3 flashing/debugging

### Adding the board to a workspace

The board directory is custom and not part of upstream Zephyr.

**Option A — custom board root:**

```bash
west build -b iot_sensor_node_esp32c3 samples/hello_world \
    -- -DBOARD_ROOT=<path-to-this-repo>/zephyr
```

This assumes the board directory lives at:

```text
<repo>/zephyr/boards/others/iot_sensor_node_esp32c3/
```

**Option B — copy the board directory into the Zephyr tree:**

```text
zephyr/boards/others/iot_sensor_node_esp32c3/
```

### SE050 / NXP Plug & Trust

SE050 support uses NXP's Plug & Trust Nano Package rather than a native in-tree Zephyr SE050 driver.

The module used for Rev 2 development is placed under:

```text
modules/crypto/nxp-plugandtrust/
```

Example build command for NXP's `se05x_GetInfo` Zephyr example:

```powershell
west build -p always `
  -b iot_sensor_node_esp32c3 `
  ..\modules\crypto\nxp-plugandtrust\examples\se05x_GetInfo\zephyr `
  -- -DZEPHYR_EXTRA_MODULES="C:\Users\Admin\zephyr_workspace\zephyrproject\modules\crypto\nxp-plugandtrust"
```

The workspace path is machine-specific; the important part is making the NXP module visible through `ZEPHYR_EXTRA_MODULES`.

---

## 8. Building Applications

The board is selected by its identifier:

```bash
west build -b iot_sensor_node_esp32c3 samples/hello_world
```

Use a pristine build after changing board-level Devicetree, pinctrl, Kconfig, or module configuration:

```bash
west build -p always -b iot_sensor_node_esp32c3 samples/hello_world
```

### Rev 2 validation builds

#### Base board

```bash
west build -p always -b iot_sensor_node_esp32c3 samples/hello_world
```

Validates board discovery, Devicetree generation, Kconfig processing, compilation, linking, and ESP32-C3 image generation.

#### BQ27441 fuel gauge

```bash
west build -p always -b iot_sensor_node_esp32c3 samples/sensor/sensor_shell
```

This validates the BQ27441 node and Zephyr sensor-subsystem integration.

#### DS3231 RTC

The RTC sample targets the functional RTC child through:

```dts
aliases {
    rtc = &ds3231_rtc;
};
```

#### SE050E2

NXP's `se05x_GetInfo` Zephyr example is built using the Plug & Trust external module described in Section 7.

### Application Overlay

Board-level hardware description stays fixed; application-specific needs are layered in through an overlay:

```text
app/
├── CMakeLists.txt
├── prj.conf
├── src/
│   └── main.c
└── boards/
    └── iot_sensor_node_esp32c3.overlay
```

### Application Configuration

Zephyr subsystems required by an application are enabled in `prj.conf`, not forced globally by the board definition:

```conf
CONFIG_GPIO=y
CONFIG_I2C=y
CONFIG_SPI=y
CONFIG_SENSOR=y
CONFIG_RTC=y
```

Only the subsystems required by the application need to be enabled.

---

## 9. Problems Encountered & Resolutions

| Problem | Cause | Resolution |
|---|---|---|
| `undefined reference to 'k_malloc'` at link time | ESP32-C3 Espressif HAL components required Zephyr dynamic allocation but the board lacked the required board-level heap headroom | Added `HEAP_MEM_POOL_ADD_SIZE_BOARD = 4096` in board `Kconfig` |
| ADC child-node `reg` / address-cell error | ADC channel child nodes were inheriting the `/soc` address/size-cell format instead of a channel-oriented child format | Added `#address-cells = <1>;` and `#size-cells = <0>;` to `&adc0` |
| `jedec,spi-nor jedec-id required for non-runtime SFDP` / `size required ...` | W25Q32 node lacked the required identification and size properties | Added explicit JEDEC ID and flash-size properties |
| SD card not represented correctly | Missing/incorrect Zephyr SPI SDHC binding structure | Added `zephyr,sdhc-spi-slot` with nested `zephyr,sdmmc-disk` child |
| RTC sample: `__device_dts_ord_DT_N_ALIAS_rtc_ORD` undeclared | The sample uses `DT_ALIAS(rtc)`, but the custom board initially had no `rtc` alias | Added `rtc = &ds3231_rtc;` |
| RTC alias initially targeted the DS3231 MFD parent | The parent represents shared chip infrastructure; the RTC API is implemented by the child | Pointed the alias to `ds3231_rtc` |
| NXP SE050 example aborted with `GPIO_ESP32 ... GPIO with value n` | NXP example `prj.conf` explicitly set `CONFIG_GPIO=n`, conflicting with ESP32 I²C/UART driver requirements | Changed the example configuration to `CONFIG_GPIO=y` |
| No native SE050 Devicetree binding used | Integration uses NXP Plug & Trust rather than an in-tree Zephyr SE050 driver | Exposed the I²C transport with `se05x-i2c = &i2c0;` instead of inventing a device binding |

Each issue was resolved at the board-definition or middleware-integration level rather than through application-specific workarounds.

---

## 10. Current Status

| Area | Status |
|---|---|
| Custom board discovery | ✅ Build-validated |
| Board metadata / build integration | ✅ Complete |
| Devicetree generation | ✅ Build-validated |
| ESP32-C3 pinctrl | ✅ Build-validated |
| Kconfig / board heap / sysbuild | ✅ Build-validated |
| UART / console | ✅ Build-validated |
| GPIO / BOOT | ✅ Build-validated |
| ADC | ✅ Build-validated |
| BME280 / I²C | ✅ Build-validated |
| SPI NOR / W25Q32 | ✅ Build-validated |
| microSD | ✅ Build-validated |
| DS3231 RTC | ✅ Build-validated |
| BQ27441 fuel gauge | ✅ Build-validated |
| SE050 Plug & Trust integration | ✅ Build-validated |
| Native USB/JTAG / OpenOCD | ✅ Configured |

The Rev 2 board definition has been validated through Zephyr's build pipeline:

```text
Board discovery
    ↓
Devicetree preprocessing / generation
    ↓
Kconfig processing
    ↓
Compilation
    ↓
Linking
    ↓
ESP32-C3 image generation
```

Relevant Zephyr samples and the NXP middleware example have built successfully against the current board definition.

---

## 11. References

**Zephyr Project** — board porting guide, Devicetree documentation, Kconfig documentation, RTC API, sensor API, storage subsystem, and ESP32-C3 board/SoC support.

**Espressif** — ESP32-C3 documentation, ESP32-C3-WROOM-02 datasheet, ESP32-C3 Technical Reference Manual, Espressif HAL, native USB/JTAG, and Espressif OpenOCD.

**NXP** — EdgeLock SE050E2 documentation and Plug & Trust Nano Package / Zephyr examples.

**Texas Instruments** — BQ27441-G1A fuel-gauge documentation and TPS63802 regulator documentation.

**Analog Devices / Maxim Integrated** — DS3231SN datasheet and RTC documentation.

**Other component documentation** — BME280, W25Q32JV, CP2102N, MCP73871, MAX4466, TEMT6000, and SD card interface documentation.

**Reference implementation** — Zephyr's built-in ESP32-C3-DevKitC board support, used as the adaptation baseline for the custom board port.

---

## 12. Revision History

### Zephyr v1.0 — IoT Development Board

Initial custom board port covering the original ESP32-C3 IoT platform:

- custom board discovery and metadata
- Kconfig / heap integration
- custom Devicetree and pinctrl
- UART console
- BOOT GPIO
- BME280
- ADC sensor channels
- W25Q32 SPI NOR
- microSD over SPI
- native USB/JTAG configuration

### Zephyr v2.0 — Secure-Ready Battery-Powered Edge Logger

Extends the Rev 1 board support for Hardware Rev 2:

- DS3231SN MFD/RTC integration
- RTC alias targeting the functional RTC child
- GPIO8 `INT/SQW` allocation
- BQ27441-G1A fuel-gauge node
- NXP SE050E2 I²C transport alias
- NXP Plug & Trust build integration
- Rev 2 subsystem build validation

Hardware runtime validation remains pending Rev 2 PCB fabrication and bring-up.
