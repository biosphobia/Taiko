# Third-party components

TaikoMove itself is licensed under the GNU GPL v2 or later (see LICENSE). The native hardware
extension (`addons/taiko_hw`) links the following components:

| Component | License | Used for |
|-----------|---------|----------|
| [Godot Engine](https://godotengine.org) 4.5 | MIT | Game engine |
| [godot-cpp](https://github.com/godotengine/godot-cpp) | MIT | GDExtension bindings |
| [hidapi](https://github.com/libusb/hidapi) 0.15 | BSD-3-Clause / HIDAPI license | PS Move HID access (Bluetooth and USB) |
| [libusb](https://libusb.info) 1.0.29 | LGPL-2.1 | PS3 Eye USB access (statically linked; relink with the provided build scripts) |
| [PS3EYEDriver](https://github.com/inspirit/PS3EYEDriver) | MIT + GPL-2.0 (code derived from the Linux `ov534` driver) | PS3 Eye camera driver |
| [psmoveapi](https://github.com/thp/psmoveapi) | BSD-2-Clause | Reference for the PS Move report formats, calibration blob layout and Windows pairing procedure (re-implemented in `native/src`) |

Vendored sources live in `native/thirdparty/` together with their license files. One local change was
made to hidapi (`windows/hidapi_cfgmgr32.h`: include `<wtypes.h>` so the header compiles with mingw-w64).

All bundled songs and sound effects are synthesized by `tools/generate_assets.py` and carry no
third-party rights. osu! beatmaps you import remain the property of their creators.
