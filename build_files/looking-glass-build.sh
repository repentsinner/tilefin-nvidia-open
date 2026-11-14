#!/usr/bin/env bash
# Builds the Looking Glass client in a throwaway stage of the Containerfile
# (§spec:looking-glass-client) and stages it under /out for the image.
set -euo pipefail

# The client and the guest's host application speak a release-specific
# protocol, so the guest installs the host from this same release.
readonly LG_TAG="B7"
# Commit the annotated B7 tag points at (tag object c15f3410...). Checked after
# the clone so a moved tag fails the build instead of shipping other code.
readonly LG_COMMIT="27fe47cbe2a3a8da986d310ab866f0b646ed68f5"
readonly LG_REPO="https://github.com/gnif/LookingGlass.git"
readonly OUT="/out"

dnf5 -y -q install --setopt=install_weak_deps=False \
    git gcc gcc-c++ cmake make coreutils gawk \
    'pkgconfig(libpipewire-0.3)' 'pkgconfig(libpulse)' 'pkgconfig(samplerate)' \
    'pkgconfig(wayland-client)' 'pkgconfig(wayland-cursor)' 'pkgconfig(wayland-egl)' \
    'pkgconfig(xkbcommon)' 'pkgconfig(libdecor-0)' \
    'pkgconfig(x11)' 'pkgconfig(xi)' 'pkgconfig(xfixes)' 'pkgconfig(xscrnsaver)' \
    'pkgconfig(xinerama)' 'pkgconfig(xcursor)' 'pkgconfig(xpresent)' 'pkgconfig(xrandr)' \
    'pkgconfig(egl)' 'pkgconfig(gl)' 'pkgconfig(fontconfig)' \
    'pkgconfig(spice-protocol)' 'pkgconfig(nettle)' 'pkgconfig(hogweed)'

git clone -q --depth 1 --branch "$LG_TAG" --recurse-submodules --shallow-submodules \
    "$LG_REPO" /src
test "$(git -C /src rev-parse HEAD)" = "$LG_COMMIT"

# OPTIMIZE_FOR_NATIVE defaults to ON upstream and compiles for the build
# machine's CPU. On a builder with AVX-512 that yields a client that dies with
# SIGILL before main() on CPUs without it, which is what the COPR package does.
# CI runners carry AVX-512 as often as not, so it stays off here too.
#
# The rest keeps a 2025 release building on Fedora 44's toolchain:
# - CMAKE_POLICY_VERSION_MINIMUM: CMake 4 rejects a bundled library's
#   cmake_minimum_required below 3.5.
# - -Wno-error=maybe-uninitialized: GCC 16 flags the bundled nanosvg, and the
#   client builds with -Werror. The warning still prints.
# - ENABLE_BACKTRACE=OFF: the crash backtrace links Fedora's static libbfd,
#   which needs zstd the client's build does not add. It only prints a stack
#   trace when the client crashes.
cmake -S /src/client -B /build -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DOPTIMIZE_FOR_NATIVE=OFF \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_C_FLAGS="-Wno-error=maybe-uninitialized" \
    -DENABLE_BACKTRACE=OFF \
    -DENABLE_OPENGL=ON -DENABLE_EGL=ON -DENABLE_X11=ON -DENABLE_WAYLAND=ON \
    -DENABLE_LIBDECOR=ON -DENABLE_PIPEWIRE=ON -DENABLE_PULSEAUDIO=ON
cmake --build /build -j"$(nproc)"

install -Dm755 /build/looking-glass-client "$OUT/usr/bin/looking-glass-client"
install -Dm644 /src/resources/lg-logo.svg \
    "$OUT/usr/share/icons/hicolor/scalable/apps/looking-glass-client.svg"

# Fail the build rather than ship a client that only runs on AVX-512 CPUs.
if objdump -d --no-show-raw-insn "$OUT/usr/bin/looking-glass-client" | grep -q '%zmm'; then
    echo "looking-glass-client uses AVX-512 registers; host-CPU tuning leaked in" >&2
    exit 1
fi
