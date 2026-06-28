# QMK Keymaps

This directory keeps active keymaps for two GMMK Pro ANSI boards.

## Boards

- `gmmk_pro_rev1_ansi_gmmk_pro_rev1_ansi_mbp.json`
  - Target: `gmmk/pro/rev1/ansi`
  - MCU/bootloader: STM32F303 / `stm32-dfu`
  - Normal QMK USB ID: `320f:5044`
  - Bootloader USB ID: usually `0483:df11`

- `gmmk_pro_rev2_ansi_gmmk_pro_rev2_ansi_mbp.json`
  - Target: `gmmk/pro/rev2/ansi`
  - MCU/bootloader: WB32F3G71 / `wb32-dfu`
  - Stock USB ID seen before flashing: `320f:5092` (`GMMKPRO-WB`)
  - Normal QMK USB ID: `320f:5044`
  - Bootloader USB ID: `342d:dfa0`

## Build Tool PATH

The QMK toolchain is installed through Homebrew, but the compiler tools are keg-only. Use this PATH prefix when compiling or flashing:

```sh
export PATH="/opt/homebrew/opt/arm-none-eabi-binutils/bin:/opt/homebrew/opt/arm-none-eabi-gcc@8/bin:/opt/homebrew/opt/avr-gcc@8/bin:$PATH"
```

## Compile

```sh
qmk compile qmk/gmmk_pro_rev1_ansi_gmmk_pro_rev1_ansi_mbp.json
qmk compile qmk/gmmk_pro_rev2_ansi_gmmk_pro_rev2_ansi_mbp.json
```

## Maintenance

The rev1 and rev2 ANSI layouts have the same 83 key positions. For layout changes, edit one JSON file, then port the shared keymap fields to the other board while preserving each file's board-specific `keyboard` and `keymap` values.

For board-specific behavior, edit only the affected board's JSON.

## Flash

Verify the board identity before flashing. Do not flash the rev1 STM32 build to a stock `GMMKPRO-WB` board.

Rev1:

```sh
qmk flash qmk/gmmk_pro_rev1_ansi_gmmk_pro_rev1_ansi_mbp.json
```

Rev2:

```sh
qmk flash qmk/gmmk_pro_rev2_ansi_gmmk_pro_rev2_ansi_mbp.json
```

If `qmk flash` cannot find the WB32 flasher for rev2, install it with:

```sh
brew install wb32-dfu-updater_cli
```

## Bootloader

For either board, enter bootloader with one of:

- Hold the reset switch on the bottom side of the PCB while connecting USB.
- Hold `Esc` while connecting USB. This can also clear persistent settings.

The physical reset switch is the most reliable method for stock firmware.
