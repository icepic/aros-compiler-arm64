#!/bin/bash
# Builds the aarch64-raspi kernel pair (aros-aarch64-bsp.rom + aros-aarch64-raspi.img)
# in the build container, after ../build/build.sh has built the toolchain in /aros.
#   PATCH=alphafix  apply vcgfx-hvs6-opaque-screens.patch (default); PATCH=none for upstream
set -eux
cd /aros
exec > >(tee -a /aros/run-kernel.log) 2>&1
VC=arch/arm-native/soc/broadcom/2708/hidd/vcgfx
git -C AROS checkout -- $VC/vcgfx_hvs6.c
# BCM2712 display and HVS planes are compiled out upstream; the Pi 5 needs both.
sed -i 's/^#define VCGFX_PLANES        0$/#define VCGFX_PLANES        1/'        AROS/$VC/vcgfx_planes.c
sed -i 's/^#define VCGFX_BCM2712_ENABLE 0$/#define VCGFX_BCM2712_ENABLE 1/' AROS/$VC/vcgfx_init.c
[ "${PATCH:-alphafix}" = none ] || git -C AROS apply /repo/pi500/vcgfx-hvs6-opaque-screens.patch

# hvsdump: diagnostic tool, built with the kernel so it is in the same tree.
mkdir -p AROS/workbench/tools/hvsdump
cp /repo/pi500/hvsdump/* AROS/workbench/tools/hvsdump/

cd build
make kernel-mbox-bcm2708
for try in 1 2 3; do
    if make -j"${JOBS:-2}" kernel-raspi-aarch64 kernel-package-raspi-aarch64; then break; fi
    [ "$try" = 3 ] && exit 2
done
make distfiles-raspi-aarch64le-bootimg
make workbench-tools-hvsdump
A=/aros/build/bin/raspi-aarch64/AROS
mkdir -p /out
cp -v "$A/aros-aarch64-bsp.rom" "$A/aros-aarch64-raspi.img" "$A/Tools/hvsdump" /out/
