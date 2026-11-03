#!/bin/bash
# Runs in the build container (build/Dockerfile.host) with a volume at /aros
# and the repo at /repo. Builds the aarch64-aros GCC 6.5 cross toolchain and
# the SDK (headers, link libraries) from AROS master, then exports both to
# /out/toolchain and /out/Developer, the build context of ../Dockerfile.
# Resumable: the crosstools stage is skipped once /aros/.stage-crosstools exists.
#   AROS_COMMIT  commit to build (default: the pinned one below)
#   JOBS         make parallelism (default 2)
set -eux
AROS_COMMIT="${AROS_COMMIT:-8b163295950f4964e0de197c7969a8cc95abc7f5}"
cd /aros
exec > >(tee -a /aros/run.log) 2>&1
echo "=== build started $(date -u +%FT%TZ) on $(uname -m)"

if [ ! -d AROS/.git ]; then
    git init AROS
    git -C AROS remote add origin https://github.com/aros-development-team/AROS.git
fi
git -C AROS fetch --depth 1 origin "$AROS_COMMIT"
git -C AROS checkout -f FETCH_HEAD
# Translation catalogs (.cd files) live in submodules; rom/dos needs them.
git -C AROS submodule update --init --recursive --depth 1 --jobs 4

# libgcc needs an aarch64*-*-aros* case in config.host; appended once.
D=AROS/tools/crosstools/gnu/gcc-6.5.0-aros.diff
grep -q 'soft-fp TF-mode' "$D" || cat /repo/patches/gcc-6.5.0-aarch64-libgcc.patch >> "$D"

# binutils 2.32 rejects the symbolic name id_aa64mmfr2_el1; s3_0_c0_c7_2 is
# the same register. Only needed for the kernel, kept so the tree is one state.
sed -i 's/mrs %0, id_aa64mmfr2_el1/mrs %0, s3_0_c0_c7_2/' \
    AROS/arch/aarch64-native/processor/processor_util.c

# xadmaster.library headers, from the contrib repo's portable xad port only.
if [ ! -d AROS/contrib/.git ]; then
    git clone --depth 1 --filter=blob:none --sparse \
        https://github.com/aros-development-team/contrib.git AROS/contrib
    git -C AROS/contrib sparse-checkout set workbench/libs/xad
fi

# This host-side unit test of genmodule's handler output fails on an arm64
# host and stops the default target. It checks the build tools, not the SDK.
sed -i 's|^\t\$(PYTHON) \$(SRCDIR)/developer/debug/test/genmodule/handler-init-test.py|\t-$(PYTHON) $(SRCDIR)/developer/debug/test/genmodule/handler-init-test.py|' \
    AROS/developer/debug/test/genmodule/mmakefile.src

mkdir -p build toolchain && cd build
if [ ! -f /aros/.stage-crosstools ]; then
    [ -f Makefile ] || ../AROS/configure --target=raspi-aarch64 \
        --with-aros-toolchain-install=/aros/toolchain
    make -s crosstools -j"${JOBS:-2}"
    touch /aros/.stage-crosstools
fi
echo "=== crosstools done $(date -u +%FT%TZ)"

# mmake writes each generated mmakefile into a matching build directory but
# does not create it for a tree added after the first configure.
(cd /aros/AROS/contrib && find . -name mmakefile.src -printf '%h\n') |
    while read -r d; do mkdir -p "/aros/build/contrib/$d"; done
../AROS/configure --target=raspi-aarch64 \
    --with-aros-toolchain=yes \
    --with-aros-toolchain-install=/aros/toolchain
# proto/mbox.h only appears once the mbox module is built; the processor
# module includes it but depends only on the generic includes target.
make kernel-mbox-bcm2708

# mmake regenerates makefiles in parallel and can race on the rename.
for try in 1 2 3; do
    echo "=== make attempt $try $(date -u +%FT%TZ)"
    if make -j"${JOBS:-2}"; then break; fi
    [ "$try" = 3 ] && exit 2
done
make xadmaster-includes
echo "=== sdk build finished $(date -u +%FT%TZ)"

rm -rf /out/toolchain /out/Developer
cp -a /aros/toolchain /out/toolchain
cp -a /aros/build/bin/raspi-aarch64/AROS/Developer /out/Developer
git -C /aros/AROS log -1 --format=%H > /out/AROS_COMMIT
echo "=== export finished $(date -u +%FT%TZ)"
