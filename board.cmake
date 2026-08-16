if(NOT "${OPENOCD}" MATCHES "^${ESPRESSIF_TOOLCHAIN_PATH}/.*")
  set(OPENOCD OPENOCD-NOTFOUND)
endif()
find_program(OPENOCD openocd PATHS ${ESPRESSIF_TOOLCHAIN_PATH}/openocd-esp32/bin NO_DEFAULT_PATH)

include(${ZEPHYR_BASE}/boards/common/esp32.board.cmake)

# TODO: If OpenOCD testing requires a specific configuration for the
# ESP32-C3 built-in USB/JTAG debug interface, add the appropriate
# board_runner_args(openocd "--config=...") here.

include(${ZEPHYR_BASE}/boards/common/openocd.board.cmake)
