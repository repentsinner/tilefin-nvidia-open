# Changelog

## [0.4.2](https://github.com/repentsinner/tilefin-nvidia-open/compare/v0.4.1...v0.4.2) (2026-02-26)


### Bug Fixes

* **build:** add missing gum package to image ([#15](https://github.com/repentsinner/tilefin-nvidia-open/issues/15)) ([a6b7f13](https://github.com/repentsinner/tilefin-nvidia-open/commit/a6b7f13482795cb263498b46ea14ad5c06a8ba7f))
* **setup-user:** add flathub user remote before flatpak install ([#17](https://github.com/repentsinner/tilefin-nvidia-open/issues/17)) ([b4b2afa](https://github.com/repentsinner/tilefin-nvidia-open/commit/b4b2afabd46b6b59b3ad7ed34cb72226fe39324f))
* **shell:** rewrite direnv hook paths for distrobox exports ([#18](https://github.com/repentsinner/tilefin-nvidia-open/issues/18)) ([c9d6473](https://github.com/repentsinner/tilefin-nvidia-open/commit/c9d6473c5c3116d8f9648d690c41636f5249a775))

## [0.4.1](https://github.com/repentsinner/tilefin-nvidia-open/compare/v0.4.0...v0.4.1) (2026-02-26)


### Features

* add additional COPR repositories for enhanced functionality ([7c0291a](https://github.com/repentsinner/tilefin-nvidia-open/commit/7c0291adb639a0b7f20048f29f12c8155939f312))
* add direnv to system utilities and enable rpm-ostreed-automatic.timer for image upgrades ([bd39695](https://github.com/repentsinner/tilefin-nvidia-open/commit/bd396954ba64861be0d7c8281791be1a9adccfff))
* Add virtualization support by installing relevant packages, enabling libvirtd, and configuring IOMMU and verbose boot kernel arguments. ([ed92220](https://github.com/repentsinner/tilefin-nvidia-open/commit/ed9222002b0f7f48fde603ba885e017281c1c509))
* Add Waybar notification indicator and configure mako for silent, history-only notifications. ([be3bcbe](https://github.com/repentsinner/tilefin-nvidia-open/commit/be3bcbe5b1bcc81306d809efd2873df544f65f49))
* **build:** rebase from bluefin-dx to base-nvidia ([2e9641b](https://github.com/repentsinner/tilefin-nvidia-open/commit/2e9641b728d55668abfe3f3d32c0a8ea847e9b67))
* enhance update check module with package summary and styling adjustments ([0c55ea5](https://github.com/repentsinner/tilefin-nvidia-open/commit/0c55ea5bf7d098f4f630de161d9ba1d7d79e5ddf))
* Implement unified compositor exit and power menu, update Hyprland configuration, and add package management guidelines. ([41345e0](https://github.com/repentsinner/tilefin-nvidia-open/commit/41345e0ba51707636e0f32f43151ba65278e66a7))
* **niri:** set VS Code default column width to 1600px ([0424d5e](https://github.com/repentsinner/tilefin-nvidia-open/commit/0424d5e5a513851fca23cce6a543457128dd45df))
* **s12:** move Flatpaks to interactive setup-user recipe with gum ([#13](https://github.com/repentsinner/tilefin-nvidia-open/issues/13)) ([b0719c5](https://github.com/repentsinner/tilefin-nvidia-open/commit/b0719c5580295f4a6cccee3095dd6800f6e14cbb))
* **s12:** move user tools to userbox distrobox container ([6046840](https://github.com/repentsinner/tilefin-nvidia-open/commit/6046840d126116cf1b61c085c43abf260a6b28b5))
* update Waybar configuration and scripts for system-wide access ([587aba3](https://github.com/repentsinner/tilefin-nvidia-open/commit/587aba3bdab0cb26a899b6514078b75d323e3502))


### Bug Fixes

* resolve hypridle crash introduced in  v0.1.3 (PR [#77](https://github.com/repentsinner/tilefin-nvidia-open/issues/77)) and improve lock/keybind config ([ae4e545](https://github.com/repentsinner/tilefin-nvidia-open/commit/ae4e545f5df7f9bdcfa3524a84e713fc5a7b7ee0))
* **shell:** add ~/.local/bin to PATH, fix ujust recipe loading ([#14](https://github.com/repentsinner/tilefin-nvidia-open/issues/14)) ([975f8f3](https://github.com/repentsinner/tilefin-nvidia-open/commit/975f8f3b0ad83c9f960990232125c4dd3b5391dc))
