# Native arm64 AROS cross-compiler image (aarch64-aros), the same layout as
# midwan/aros-compiler:aarch64-aros but without x86 emulation. The toolchain
# and SDK come from ./context/{toolchain,Developer}, produced by build/build.sh.
#
#   docker build --platform linux/arm64 -t aros-compiler:aarch64-aros-arm64 .

############################
# Stage 1: LHa for UNIX 1.14i-ac, as in the amd64 image
############################
FROM ubuntu:24.04 AS lha
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates git make gcc autoconf automake libtool && \
    rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    git clone --depth 1 --branch release-20211125 https://github.com/jca02266/lha.git /tmp/lha-src; \
    cd /tmp/lha-src; \
    aclocal && autoheader && automake --add-missing --foreign && autoconf; \
    ./configure --prefix=/opt/lha-bin; \
    make -j "$(nproc)"; \
    make install

############################
# Stage 2: runtime
############################
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.source="https://github.com/icepic/aros-compiler-arm64"
LABEL org.opencontainers.image.licenses="GPL-3.0-or-later AND APSL-1.1 AND MIT"
LABEL org.opencontainers.image.title="AROS cross-compiler (arm64 host)"
LABEL org.opencontainers.image.description="aarch64-aros GCC 6.5 toolchain, collect-aros and SDK, built natively for arm64 hosts; Clang 18 and LHa as in midwan/aros-compiler:aarch64-aros"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates make gawk file clang-18 && \
    ln -s /usr/bin/clang-18 /usr/local/bin/clang && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# The files live under /opt, as in the amd64 image. The cross-gcc spec has the
# build-time paths (/aros/...) baked in, so those are links to the real files.
COPY context/toolchain /opt/aros-toolchain
COPY context/Developer /opt/aros-build/bin/raspi-aarch64/AROS/Developer
COPY --from=lha /opt/lha-bin /opt/lha-bin
RUN mkdir -p /aros/build/bin/raspi-aarch64/AROS && \
    ln -s /opt/aros-toolchain /aros/toolchain && \
    ln -s /opt/aros-build/bin/raspi-aarch64/AROS/Developer \
          /aros/build/bin/raspi-aarch64/AROS/Developer

ENV PATH=/opt/aros-toolchain/aarch64-aros/bin:/opt/aros-toolchain:/opt/lha-bin/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /work
CMD ["bash"]
