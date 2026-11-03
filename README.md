# aros-compiler-arm64

AROS `aarch64-aros` cross-compiler image for arm64 hosts (Apple Silicon, Graviton, Raspberry Pi).
It has the layout of [`midwan/aros-compiler:aarch64-aros`](https://hub.docker.com/r/midwan/aros-compiler)
(`/opt/aros-toolchain`, `/opt/aros-build/.../Developer`, `/opt/lha-bin`, Clang 18) and runs natively.
The amd64 image's `aarch64-aros-gcc` crashes with `Illegal instruction` under Rosetta on constants such as `double *= 10.0`.

## Use

```bash
docker pull ghcr.io/icepic/aros-compiler-arm64:aarch64-aros
docker run --rm -v "$PWD":/work ghcr.io/icepic/aros-compiler-arm64:aarch64-aros \
    aarch64-aros-gcc -O2 hello.c -o hello
```

Without a registry: download `aros-compiler-arm64.tar.gz` from the [image release](https://github.com/icepic/aros-compiler-arm64/releases/tag/image-aarch64-aros-20261103), then `docker load < aros-compiler-arm64.tar.gz`. The loaded tag is `ghcr.io/icepic/aros-compiler-arm64:ci-2`; it is the same image as `:aarch64-aros`.

## Build

The image is arm64 only. `build/build.sh` builds the toolchain and SDK from AROS master at a pinned commit and exports them to `context/`:

```bash
docker build --platform linux/arm64 -t aros-build-host -f build/Dockerfile.host build
docker volume create aros-native && mkdir -p context
docker run -d --platform linux/arm64 --name aros-build -e JOBS=2 \
    -v aros-native:/aros -v "$PWD":/repo:ro -v "$PWD/context":/out \
    aros-build-host /bin/bash /repo/build/build.sh
docker wait aros-build
docker build --platform linux/arm64 -t aros-compiler:aarch64-aros .
```

The volume holds about 11 GB. A from-scratch build (GCC and binutils, then the full AROS tree) took 23 minutes on a GitHub arm64 runner (4 cores); with the `crosstools` stage cached, a rebuild takes about 5 minutes. `.github/workflows/build.yml` runs this build, the tests and the push to ghcr.io. Run the container detached: `build.sh` logs to `/aros/run.log` in the volume and resumes after an interruption.

Workarounds in `build.sh`, each needed on an arm64 host:

| Problem | Fix |
|---|---|
| libgcc has no `aarch64*-*-aros*` case | `patches/gcc-6.5.0-aarch64-libgcc.patch`, as in the amd64 image |
| translation catalogs missing, `rom/dos` fails on `MSG_*` | fetch git submodules |
| `proto/mbox.h` missing for `processor` | build `kernel-mbox-bcm2708` first |
| `id_aa64mmfr2_el1` rejected by binutils 2.32 | use the generic name `s3_0_c0_c7_2` |
| `mmakefile` rename fails for `contrib` | create the build directories before `make` |
| `test-genmodule-handlers` fails on arm64 | made non-fatal; it tests the build tools, not the SDK |

The cross-gcc spec has the build paths (`/aros/...`) baked in, so the image links them to the files under `/opt`.

## Compared with the amd64 image

Same source, `test/objtest.sh` and `test/fulltest.sh`:

| Check | Result |
|---|---|
| gcc, as, clang versions | identical (GCC 6.5.0, binutils 2.32, Clang 18.1.3) |
| `gcc -c hello.c` object | byte-identical |
| `clang --target=aarch64-aros -c` objects | byte-identical |
| `gcc -c fp.c` (`double *= 10.0`) | compiles; amd64 under Rosetta: internal compiler error |
| 10 x `gcc -c hello.c` | 0.27 s against 2.8 s |
| SDK static libraries | 166, including all 150 of the amd64 image's |

- The SDK comes from AROS master `8b16329` (2026-11-01). The amd64 image's is from October, so linked programs differ in size and this SDK has 16 more libraries.
- `Developer/Debug/Tests` (244 test programs) is absent.

## Raspberry Pi 500 / Pi 5 black screen

`pi500/` has the fix for AROS booting to a black screen on the Pi 500, the `hvsdump` diagnostic, and the kernel build script. See [pi500/README.md](pi500/README.md).

## Sources and licenses

Scripts and patches in this repository: MIT. The image contains:

| Component | Version | License | Source |
|---|---|---|---|
| GCC | 6.5.0 with AROS patches | GPL-3.0-or-later | https://github.com/aros-development-team/AROS (`tools/crosstools`) |
| binutils | 2.32 with AROS patches | GPL-3.0-or-later | same |
| AROS headers and link libraries | `8b163295950f4964e0de197c7969a8cc95abc7f5` | AROS Public License | https://github.com/aros-development-team/AROS |
| LHa for UNIX | release-20211125 | see upstream | https://github.com/jca02266/lha |
| Clang | 18 (Ubuntu 24.04) | Apache-2.0 with LLVM exceptions | Ubuntu archive |

The Dockerfile layout and the libgcc patch follow [BlitterStudio/aros-compiler-docker](https://github.com/BlitterStudio/aros-compiler-docker), which builds the amd64 image.
