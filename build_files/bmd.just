# Blackmagic Design Desktop Video driver management
#
# These recipes build and install the BMD kernel modules, firmware, and
# userspace tools on a Fedora Atomic host. The BMD tarball is not
# redistributable — download it from blackmagicdesign.com and pass the
# path to bmd-build.

export bmd_version := "15.3.1a4"
export bmd_install_dir := "/var/lib/blackmagic"
export bmd_module_dir := "/var/lib/blackmagic/modules"
export bmd_firmware_dir := "/var/lib/blackmagic/firmware"
export bmd_lib_dir := "/var/lib/blackmagic/lib"
export bmd_bin_dir := "/var/lib/blackmagic/bin"

# Build and install Blackmagic DeckLink kernel modules, firmware, and SDK library
[group('Blackmagic')]
bmd-build tarball:
    #!/usr/bin/env bash
    set -euo pipefail

    KERNEL_RELEASE="$(uname -r)"
    BUILD_DIR="$(mktemp -d /tmp/bmd-build.XXXXXXXXXX)"
    trap 'rm -rf "${BUILD_DIR}"' EXIT

    echo "==> Building Blackmagic modules for kernel ${KERNEL_RELEASE}"
    echo "  Working in ${BUILD_DIR}"

    # Extract tarball and RPM
    echo "  Extracting tarball..."
    tar xzf "{{ tarball }}" -C "${BUILD_DIR}" --strip-components=1

    RPM="${BUILD_DIR}/rpm/x86_64/desktopvideo-{{ bmd_version }}.x86_64.rpm"
    if [[ ! -f "${RPM}" ]]; then
        echo "Error: expected RPM not found at ${RPM}"
        echo "Check bmd_version (currently {{ bmd_version }}) matches the tarball."
        exit 1
    fi

    echo "  Extracting RPM..."
    RPM_ROOT="${BUILD_DIR}/rpm-root"
    mkdir -p "${RPM_ROOT}"
    cd "${RPM_ROOT}"
    rpm2cpio "${RPM}" | cpio -idm --quiet
    cd - > /dev/null

    # Build kernel modules in a Fedora container
    echo "  Building kernel modules in container..."
    SRC_IO="${RPM_ROOT}/usr/src/blackmagic-io-{{ bmd_version }}"
    SRC_BM="${RPM_ROOT}/usr/src/blackmagic-{{ bmd_version }}"

    podman run --rm \
        -v "${SRC_IO}:/build/blackmagic-io:Z" \
        -v "${SRC_BM}:/build/blackmagic:Z" \
        "registry.fedoraproject.org/fedora:$(rpm -E %fedora)" \
        bash -c "
            set -euo pipefail
            dnf install -y --setopt=install_weak_deps=False \
                kernel-devel-${KERNEL_RELEASE} gcc make elfutils-libelf-devel
            # kernel-devel installs source to /usr/src/kernels/ but the
            # /lib/modules/<ver>/build symlink requires kernel-core which
            # is too heavy for a build container. Create it manually.
            mkdir -p /lib/modules/${KERNEL_RELEASE}
            ln -sf /usr/src/kernels/${KERNEL_RELEASE} /lib/modules/${KERNEL_RELEASE}/build
            cd /build/blackmagic-io
            make KERNELRELEASE=${KERNEL_RELEASE}
            cd /build/blackmagic
            make KERNELRELEASE=${KERNEL_RELEASE}
        "

    # Install to host
    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }

    echo "==> Installing to host"

    # Kernel modules
    echo "  Installing kernel modules..."
    sudoif mkdir -p {{ bmd_module_dir }}
    sudoif cp "${SRC_IO}/blackmagic-io.ko" {{ bmd_module_dir }}/
    sudoif cp "${SRC_IO}/snd_blackmagic-io.ko" {{ bmd_module_dir }}/
    sudoif cp "${SRC_BM}/blackmagic.ko" {{ bmd_module_dir }}/

    # SELinux: label module directory so kmod_t can load them at boot
    echo "  Configuring SELinux file contexts..."
    sudoif semanage fcontext -a -t modules_object_t '{{ bmd_module_dir }}(/.*)?'  2>/dev/null \
        || sudoif semanage fcontext -m -t modules_object_t '{{ bmd_module_dir }}(/.*)?' 2>/dev/null \
        || true
    sudoif restorecon -Rv {{ bmd_module_dir }}

    # Firmware blobs
    echo "  Installing firmware..."
    sudoif mkdir -p {{ bmd_firmware_dir }}
    sudoif cp "${RPM_ROOT}"/usr/lib64/blackmagic/DesktopVideo/Firmware/*.bin {{ bmd_firmware_dir }}/

    # Shared libraries (firmware updater deps + DeckLink SDK runtime)
    echo "  Installing libraries..."
    sudoif mkdir -p {{ bmd_lib_dir }}
    sudoif cp "${RPM_ROOT}"/usr/lib64/blackmagic/DesktopVideo/lib*.so* {{ bmd_lib_dir }}/
    sudoif cp "${RPM_ROOT}"/usr/lib64/libDeckLinkAPI.so {{ bmd_lib_dir }}/

    # Make libraries discoverable via ld.so (DeckLinkAPIDispatch.cpp uses dlopen)
    echo "/var/lib/blackmagic/lib" | sudoif tee /etc/ld.so.conf.d/blackmagic.conf > /dev/null
    sudoif ldconfig

    # Firmware updater binary + PATH wrapper
    echo "  Installing firmware updater..."
    sudoif mkdir -p {{ bmd_bin_dir }}
    sudoif cp "${RPM_ROOT}"/usr/lib64/blackmagic/DesktopVideo/DesktopVideoUpdateTool {{ bmd_bin_dir }}/
    sudoif ln -sf DesktopVideoUpdateTool {{ bmd_bin_dir }}/BlackmagicFirmwareUpdater

    sudoif mkdir -p /usr/local/bin
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'export LD_LIBRARY_PATH="/var/lib/blackmagic/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
        'exec /var/lib/blackmagic/bin/BlackmagicFirmwareUpdater "$@"' \
        | sudoif tee /usr/local/bin/BlackmagicFirmwareUpdater > /dev/null
    sudoif chmod 755 /usr/local/bin/BlackmagicFirmwareUpdater

    # Udev rules (simplified — no DesktopVideoNotifier dependency)
    echo "  Installing udev rules..."
    printf '%s\n' \
        '# Blackmagic Design DeckLink device permissions' \
        'ACTION=="add", KERNEL=="blackmagic/io[0-9]*", MODE="0666"' \
        'ACTION=="add", KERNEL=="blackmagic/ttyio[0-9]*", MODE="0666"' \
        'ACTION=="add", KERNEL=="blackmagic/dv[0-9]*", MODE="0666"' \
        'ACTION=="add", KERNEL=="blackmagic/ttydv[0-9]*", SYMLINK+="blackmagic/serial%n", MODE="0666"' \
        | sudoif tee /etc/udev/rules.d/55-blackmagic.rules > /dev/null

    # Systemd service
    echo "  Installing systemd service..."
    MODULE_DIR="{{ bmd_module_dir }}"
    printf '%s\n' \
        '[Unit]' \
        'Description=Load Blackmagic DeckLink kernel modules' \
        'After=local-fs.target' \
        '' \
        '[Service]' \
        'Type=oneshot' \
        'RemainAfterExit=yes' \
        "ExecStart=/sbin/insmod ${MODULE_DIR}/blackmagic.ko" \
        "ExecStart=/sbin/insmod ${MODULE_DIR}/blackmagic-io.ko" \
        "ExecStart=/sbin/insmod ${MODULE_DIR}/snd_blackmagic-io.ko" \
        'ExecStop=/sbin/rmmod snd_blackmagic-io' \
        'ExecStop=/sbin/rmmod blackmagic-io' \
        'ExecStop=/sbin/rmmod blackmagic' \
        '' \
        '[Install]' \
        'WantedBy=multi-user.target' \
        | sudoif tee /etc/systemd/system/blackmagic-io.service > /dev/null

    sudoif systemctl daemon-reload
    sudoif systemctl enable blackmagic-io.service
    sudoif udevadm control --reload-rules

    # Load modules now
    echo "  Loading kernel modules..."
    sudoif systemctl start blackmagic-io.service

    echo ""
    echo "==> Installation complete."
    systemctl status blackmagic-io.service --no-pager
    echo ""
    echo "Verify with: BlackmagicFirmwareUpdater status"

# Uninstall Blackmagic modules, firmware, and tools from the host
[group('Blackmagic')]
[confirm("This will remove all BMD drivers and tools from the host. Continue?")]
bmd-uninstall:
    #!/usr/bin/env bash
    set -euo pipefail

    function sudoif(){
        if [[ "${UID}" -eq 0 ]]; then
            "$@"
        elif [[ "$(command -v sudo)" && -n "${SSH_ASKPASS:-}" ]] && [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            /usr/bin/sudo --askpass "$@" || exit 1
        elif [[ "$(command -v sudo)" ]]; then
            /usr/bin/sudo "$@" || exit 1
        else
            exit 1
        fi
    }

    echo "==> Uninstalling Blackmagic Design Desktop Video driver"

    # Stop and disable service
    echo "  Stopping service..."
    sudoif systemctl stop blackmagic-io.service 2>/dev/null || true
    sudoif systemctl disable blackmagic-io.service 2>/dev/null || true

    # Remove systemd service
    echo "  Removing systemd service..."
    sudoif rm -f /etc/systemd/system/blackmagic-io.service
    sudoif systemctl daemon-reload

    # Remove udev rules
    echo "  Removing udev rules..."
    sudoif rm -f /etc/udev/rules.d/55-blackmagic.rules
    sudoif udevadm control --reload-rules

    # Remove SELinux file context
    echo "  Removing SELinux file contexts..."
    sudoif semanage fcontext -d '{{ bmd_module_dir }}(/.*)?'  2>/dev/null || true

    # Remove ld.so config
    echo "  Removing library config..."
    sudoif rm -f /etc/ld.so.conf.d/blackmagic.conf
    sudoif ldconfig

    # Remove wrapper script
    echo "  Removing firmware updater wrapper..."
    sudoif rm -f /usr/local/bin/BlackmagicFirmwareUpdater

    # Remove install directory
    echo "  Removing {{ bmd_install_dir }}..."
    sudoif rm -rf {{ bmd_install_dir }}

    echo ""
    echo "==> Uninstall complete."
