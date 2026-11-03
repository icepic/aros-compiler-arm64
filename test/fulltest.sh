#!/bin/bash
# Run inside each image; $1 = label. Prints one result line per check.
cd /work/test
L=$1
SDK=/opt/aros-build/bin/raspi-aarch64/AROS/Developer
echo "$L arch:      $(uname -m)"
echo "$L gcc:       $(aarch64-aros-gcc --version | head -1)"
echo "$L clang:     $(clang --version | head -1)"
echo "$L as:        $(aarch64-aros-as --version | head -1)"
echo "$L lha:       $(lha 2>&1 | head -1)"
echo "$L libs:      $(ls $SDK/lib/*.a | wc -l) static libs, $(find $SDK -type f | wc -l) files"
chk() { n=$1; shift; if "$@" > /tmp/$n.log 2>&1; then echo "$L $n: OK"; else echo "$L $n: FAIL $(grep -m1 -E 'error|undefined' /tmp/$n.log | cut -c1-110)"; fi; }
chk link-hello  aarch64-aros-gcc hello.c -o hello.$L.link
chk link-hvsdump aarch64-aros-gcc -O2 ../pi500/hvsdump/hvsdump.c -o hvsdump.$L.link
file hvsdump.$L.link 2>/dev/null | sed "s/^/$L /" | cut -c1-150
s=$(date +%s.%N); for i in 1 2 3 4 5 6 7 8 9 10; do aarch64-aros-gcc -O2 -c hello.c -o /tmp/h$i.o; done; e=$(date +%s.%N)
echo "$L 10x gcc -c hello.c: $(echo "$e - $s" | bc 2>/dev/null || awk "BEGIN{print $e-$s}") s"
