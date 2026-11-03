# Raspberry Pi 500 black screen

AROS aarch64-raspi nightlies boot to a black screen on the Pi 500 (BCM2712 D0, bootloader 2025-05-08). Boot text and the mouse pointer show; screens do not.

Updating the Pi 500 firmware from Raspberry Pi OS also fixes it, as reported by another user on the AROS forum. The patch below was accepted upstream because it makes AROS independent of the firmware's alpha setting, as Raspberry Pi OS does.

## Cause

`vcgfx` builds every screen's HVS6 plane from a copy of the firmware's framebuffer plane entry. On this firmware that entry has per-pixel alpha (`CTL0` bits 19:18 = 0). AROS bitmaps have alpha 0, so each screen composes as transparent. The pointer has real alpha and shows.

## Fix

`vcgfx-hvs6-opaque-screens.patch` sets the alpha mask to fixed (`CTL0` bits 19:18 = 3) on that slot in `vc4_hvs6_takeover`. The cursor clears the bits again for its own alpha.

Verified on a Pi 500 by writing the same bit at runtime with `hvsdump FIXED` (`CTL0` `6000e007` to `600ce007`): the desktop appeared and was usable. A kernel built with the patch was installed on the same card; its result is not yet reported here.

## Files

| File | Purpose |
|---|---|
| `vcgfx-hvs6-opaque-screens.patch` | the fix, against AROS master `8b16329` |
| `hvsdump/` | AROS tool: prints HVS6 channel state, walks the display list, scans plane pixels. `FIXED` sets fixed alpha on large planes; `ALPHAFF` ORs `0xff000000` into plane pixels |
| `build-kernel.sh` | builds `aros-aarch64-bsp.rom`, `aros-aarch64-raspi.img` and `hvsdump` (`PATCH=none` for upstream) |

## Build

After `build/build.sh` has filled the `aros-native` volume:

```bash
docker run --rm --platform linux/arm64 -v aros-native:/aros -v "$PWD/..":/repo:ro -v "$PWD/out":/out \
    aros-build-host /bin/bash /repo/pi500/build-kernel.sh
```

## SD card

`config.txt` (FAT partition, files from `out/` beside it):

```
arm64_bit=1
kernel=aros-aarch64-raspi.img
kernel_address=0x80000
initramfs aros-aarch64-bsp.rom 0x00800000
[pi5]
enable_rp1_uart=1
```

Serial debug is on the RP1 UART0 (115200 8N1, GPIO14/15, header pins 8 and 10) with `enable_uart=1`.

## Separate bug

The nightly sometimes crashes early in boot with SMP enabled (illegal instruction at PC `0x1018`, or Data Abort DFSC `0x21`). A second boot usually goes through. Not addressed here.
