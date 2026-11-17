# Test pad: a fake controller for testing in game

An ESP32-C3 (WEMOS/LOLIN C3 Mini) that the Mac sees as a real Bluetooth Xbox One S
controller. A script on the Mac sends it presses over USB serial, so a controller-only path of
the addon (L2 + Select, the crossbar, the wheels) can be tested without a hand on a pad.

It is real hardware to the Mac, not a virtual device: macOS ignores virtual HID pads
(GameController) and a virtual pad needs an Apple-restricted entitlement.

## Status
Works on an **ESP32-C6** (built, flashed, paired, buttons reach the game). It did **not** work on a
WEMOS/LOLIN **C3 Mini**: the board advertised but its BLE receiver was deaf (an on-board scan heard 0
adverts while WiFi received fine), so a connect request never arrived. Use a C6 (or another board
whose BLE receives).

## Set up
1. `tools/pad/setup.sh` (arduino-cli, the ESP32 core, NimBLE-Arduino 2.1.2, Callback and
   ESP32-BLE-CompositeHID).
2. Plug the board in with a data cable. If `/dev/cu.usbmodem*` doesn't show, hold BOOT while
   plugging in.
3. `PAD_FQBN="esp32:esp32:esp32c6:CDCOnBoot=cdc" tools/pad/flash.sh` (a C3 Mini:
   `esp32:esp32:lolin_c3_mini:CDCOnBoot=default`, the default).
4. System Settings > Bluetooth > pair "IF Test Pad" (it shows as an Xbox
   controller). It reconnects by itself after that. The game needs Options > Gamepad (Alpha)
   > Enable Gamepad UI on.

## Use
    tools/pad/pad.py status
    tools/pad/pad.py press A
    tools/pad/pad.py press LT+SELECT 150
    tools/pad/pad.py "stick L 0 1; wait 800; stick L 0 0"

Items: buttons `A B X Y LB RB L3 R3 SELECT START HOME SHARE`, triggers `LT RT`, d-pad
`UP DOWN LEFT RIGHT`, PlayStation aliases (`CROSS CIRCLE SQUARE TRIANGLE L1 R1 L2 R2 CREATE
OPTIONS`). Full list in the header of `firmware/firmware.ino`.

## First run: what to check
- `status` says `connected=1` once the Mac has it paired.
- A press shows in the game (the crossbar pages, a window moves).
- Stick Y: the firmware passes y = 1 as "up"; if the character walks backwards, flip the
  sign in `firmware.ino`.
- Select and Start reach the game (Select is the pad's View, Start its Menu).
- If macOS pairs it but WoW ignores it: try `XboxSeriesXControllerDeviceConfiguration`
  (change one line in `setup()`), or the library's DualSense device.
- The port is opened without toggling DTR/RTS on purpose: on the C3's USB serial those
  toggles can reset the chip.

## Things that bit (esp32 core 3.3.12)
- `NimBLE-Arduino` must be 2.5.2: 2.1.2 crashed in the BT controller init (`r_lld_env_init`).
- `ESP32-BLE-CompositeHID` 0.4.0 calls `NimBLEDevice::setDefaultPhy`, which only exists with
  extended advertising: wrap that line in `#if CONFIG_BT_NIMBLE_EXT_ADV` (in
  `~/Documents/Arduino/libraries/ESP32-BLE-CompositeHID/BleCompositeHID.cpp`).
- The device name is short ("IF Test Pad"): a longer one doesn't fit the 31-byte advert with the
  appearance and the HID UUID, so macOS lists it as "Bluetooth Device".
- `~/Documents` is iCloud-synced and can fill a library with "file 2.c" copies: delete them if a build
  fails with conflicting types.
- Serial reads need no DTR toggling. `PAD_EXTRA_FLAGS` adds compile flags (`-DPAD_TXPOWER=<dBm>`).
- A BLE scan from the Mac (Python `bleak`) needs a host app with Bluetooth access: run it from
  Terminal.app (`open -a Terminal x.command`), not from the Claude app.
