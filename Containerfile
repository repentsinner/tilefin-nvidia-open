# Allow build scripts to be referenced without being copied into the final image
FROM scratch AS ctx
COPY build_files /

# AJA Corvid44 kernel module build stage
FROM ghcr.io/ublue-os/base-nvidia:gts AS aja-kmod-builder
RUN dnf5 install -y kernel-devel gcc make git && dnf5 clean all
ARG AJA_VERSION=ntv2_17_6_0_hotfix1
RUN git clone --depth 1 --branch ${AJA_VERSION} \
      https://github.com/aja-video/libajantv2.git /build/libajantv2
RUN KVERSION=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}') && \
    AJA_DRIVER_KVERSION=${KVERSION} make -C /build/libajantv2/driver/linux

# Base Image: Universal Blue base with Nvidia open kernel modules
# No desktop environment — we add niri + wayland stack in build.sh
FROM ghcr.io/ublue-os/base-nvidia:gts

### MODIFICATIONS
## make modifications desired in your image and install packages by modifying the build.sh script
## the following RUN directive does all the things required to run "build.sh" as recommended.

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

# Install AJA kernel module into final image
RUN --mount=type=bind,from=aja-kmod-builder,source=/build/libajantv2/bin,target=/tmp/aja \
    KVERSION=$(rpm -q kernel --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}') && \
    install -Dm644 /tmp/aja/ajantv2.ko \
      /usr/lib/modules/${KVERSION}/extra/ajantv2/ajantv2.ko && \
    depmod ${KVERSION}

### LINTING
## Verify final image and contents are correct.
RUN bootc container lint
