#!/bin/bash
# Compile-only tests; prints a one-line result per case. $1 = label.
cd /work/test
L=$1
SDK=/opt/aros-build/bin/raspi-aarch64/AROS/Developer
run() { # name, command...
    n=$1; shift
    if "$@" > /tmp/$n.log 2>&1; then
        echo "$L $n OK   $(sha256sum $OUT 2>/dev/null | cut -c1-16) $(stat -c %s $OUT 2>/dev/null)"
    else
        echo "$L $n FAIL $(grep -m1 -E 'internal compiler error|error' /tmp/$n.log | cut -c1-90)"
    fi
}
OUT=hello.$L.gcc.o;  run gcc-hello  aarch64-aros-gcc -O2 -c hello.c -o $OUT
OUT=fp.$L.gcc.o;     run gcc-fp     aarch64-aros-gcc -O2 -c fp.c -o $OUT
OUT=hello.$L.clang.o; run clang-hello clang --target=aarch64-aros --sysroot="$SDK" -fno-pic -fno-pie -mcmodel=large -D__AROS__ -O2 -I"$SDK/include" -idirafter "$SDK/include/aros/posixc" -idirafter "$SDK/include/aros/stdc" -c hello.c -o $OUT
OUT=fp.$L.clang.o;   run clang-fp   clang --target=aarch64-aros --sysroot="$SDK" -fno-pic -fno-pie -mcmodel=large -D__AROS__ -O2 -I"$SDK/include" -idirafter "$SDK/include/aros/posixc" -idirafter "$SDK/include/aros/stdc" -c fp.c -o $OUT
