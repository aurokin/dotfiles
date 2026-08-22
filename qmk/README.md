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

## Workstation Switching

The keyboard and mouse are switched independently from the displays and shared
USB/audio devices:

| Hardware | Responsibility | Control method |
| --- | --- | --- |
| [ATEN CS724KM](https://www.aten.com/global/en/products/kvm/desktop-kvm-switches/cs724km/) | Keyboard and mouse across four hosts | QMK key bindings below |
| [TESmart DKS403-M24](https://www.tesmart.com/products/dks403-m24) | Three monitors across four hosts | Front panel or IR remote |
| TESmart DKS403-M24 | Shared USB 3 and audio focus | Front-panel focus locks |

The main keyboard is connected to the ATEN, so its key presses do not reach the
TESmart keyboard input. Monitor routing therefore uses the TESmart front panel
or IR remote rather than TESmart keyboard hotkeys. USB and audio can be parked
on a host with their independent front-panel locks.

See the [ATEN CS724KM manual](https://assets.aten.com/product/manual/cs724km_um_w_2021-05-13.pdf)
and [TESmart DKS403-M24 manual](https://support.tesmart.com/hc/en-us/article_attachments/53712293775897)
for the hardware controls and connection diagrams.

### ATEN Host Key Bindings

Caps Lock and the right Fn key both momentarily activate the Fn layer. Host
selection sends the ATEN sequence `Scroll Lock`, `Scroll Lock`, host number,
`Enter`.

| Binding | ATEN host |
| --- | ---: |
| `Fn+,` | 1 |
| `Fn+.` | 2 |
| `Fn+/` | 3 |
| `Fn+Right Shift` | 4 |

Normal Right Shift is unchanged; only its Fn-layer action selects host 4.

### Rollover Compatibility

Keep these keyboards in the default 6KRO mode while using the ATEN CS724KM.
Standard HID reports support six ordinary keys plus all eight modifiers at once,
which covers normal gaming input while retaining compatibility with the ATEN and
pre-boot firmware. QMK's NKRO mode is not required for ordinary gaming and can
break keyboard input through some KVMs and BIOSes.

NKRO support is explicitly disabled in both maintained keymaps, and the former
Fn-layer `NK_ON` position in the far-right column aligned with the Q row is
mapped to `KC_NO`. The old binding persisted NKRO in EEPROM and caused the ATEN
to lose punctuation, function keys, and switching macros. Future firmware now
exposes only the standard 6KRO keyboard report, so there is no persistent NKRO
mode or key binding that can recreate the failure.

If an already-flashed keyboard has incompatible persistent USB state, clear its
QMK EEPROM without replacing the keymap:

1. Connect the keyboard directly to a computer, bypassing the ATEN.
2. Unplug the keyboard.
3. Hold `Esc` while reconnecting it for about three seconds.
4. Release `Esc`, then unplug and reconnect normally once.
5. Verify punctuation directly before reconnecting the ATEN keyboard port.

This also resets saved lighting preferences; restore those after keyboard/KVM
operation is verified.

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
