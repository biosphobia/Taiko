# TaikoMove

A full Taiko-style rhythm game for PC that you play by **drumming in the air (or on a pillow) with
PlayStation Move controllers**, tracked by a **PS3 Eye camera**. Built with Godot 4.5 and a native
extension that talks to the controllers and camera directly, with the whole input path designed
around timing accuracy and low latency.

![Windows](https://img.shields.io/badge/platform-Windows%20x64-blue) ![Godot](https://img.shields.io/badge/Godot-4.5-478cbf)

## Features

- **Taiko gameplay**: Don / Ka notes, big notes (hit with both hands for double score), drumrolls,
  balloons, combo, soul gauge with clear line, GREAT/OK/MISS judgements with osu!taiko OD-based or
  arcade timing windows, results with rank, timing statistics and a hit-error histogram.
- **PS Move controllers** (PS3 model CECH-ZCM1 and the PS4 model CECH-ZCM2): swing detection from
  the IMU at the controller's native report rate, button input for menus, LED colors, rumble,
  battery display, USB pairing helper (Windows).
- **PS3 Eye camera tracking**: colored-sphere tracking at up to 187 fps decides *where* you hit the
  virtual drum: center = Don, rim = Ka, left/right side = hand. Works without the camera too
  (twist the controller or hold the trigger for Ka).
- **Calibration wizard**: hand assignment, Bluetooth pairing, hit-sensitivity auto-calibration
  from your own strokes, camera exposure/gain with auto exposure, per-controller color sampling,
  drum-zone capture, and a metronome test that measures and applies your input offset.
- **Custom songs**: import osu!taiko beatmaps (`.osz` archives, `.osu` files or folders) from the
  song select screen, by drag and drop, or by copying them into the songs folder. osu!standard maps
  are converted with taiko conversion rules.
- **Unlockables**: earn coins per play and unlock controller LED colors (the light color of each
  hand), drum skins, note skins, stage themes and titles; some unlock through achievements.
- **Keyboard play** (D F J K) works everywhere, so the game is playable without any hardware.
- Bundled with four synthesized demo songs (three difficulties each) and an offset calibration track.

## Download / build

The Windows build is produced by GitHub Actions on every push and attached to tagged releases:

1. Go to **Actions → Build → latest run → Artifacts** (or **Releases** for tagged versions) and
   download `TaikoMove-windows-x64.zip`.
2. Unzip anywhere and run `TaikoMove.exe`. Everything (game data, songs, the hardware extension
   `libtaiko_hw.windows.template_release.x86_64.dll`) is inside the folder; nothing to install.
   `TaikoMove.console.exe` is the same game with a console window for diagnostics.

### Building locally

```
git clone --recursive <this repo>
# native extension (Linux host, cross-compiles the Windows DLL with mingw-w64)
sudo apt install mingw-w64 libusb-1.0-0-dev libudev-dev && pip install scons
cd native && scons platform=windows target=template_release use_mingw=yes && scons platform=linux target=template_release
# game: open the project in Godot 4.5 (or export headless)
godot --headless --path . --export-release "Windows Desktop" build/windows/TaikoMove.exe
```

Tests: `native/tests/test_hit_detector.cpp` (hit detector on synthetic strokes),
`godot --headless -s tests/run_tests.gd` (chart parser and judge), and
`TAIKO_TEST=1 TAIKO_HW_HEADLESS=1 godot --headless res://tests/smoke.tscn` (every scene plus a
full chart played through the native extension with virtual controllers).

## Hardware setup

**Controllers** connect over Bluetooth like on a console. On Windows, pairing a Move needs help:
plug the controller in over USB, open *Setup & Calibration → Controllers* and press *Pair* (run the
game as Administrator for this step, it registers the controller with the Bluetooth stack). Then
unplug the cable and press the PS button until the red light stays on. Controllers already paired
with PSMoveService or psmoveapi work as they are. PS4 Move controllers also work while they stay
plugged in over USB.

**Camera**: the PS3 Eye has no Windows driver; install the generic WinUSB driver once with
[Zadig](https://zadig.akeo.ie): *Options → List all devices*, pick **USB Camera-B4.09.24.1**
(VID 1415, PID 2000), choose **WinUSB**, *Install Driver*. Use a USB 2.0 port. Place the camera
above the screen looking down at the space where you drum, so the drum surface is visible as an
ellipse. Point the glowing spheres toward the camera.

**Playing surface**: air drumming works out of the box. A pillow, drum practice pad or a table gives
a sharper impact; switch *Hit mode* to *Surface* (or *Hybrid*) in Settings for that.

## Accuracy and latency: how the input path works

- Every controller has its own reader thread that blocks on the HID report (no polling delay).
  Bluetooth delivery jitter and batching are removed by a software PLL locked to the controller's
  report sequence numbers, so each IMU sample gets a smooth timestamp on the monotonic clock.
- The hit detector runs on the raw samples (about 175 samples/s on a PS3 Move, one per report on a
  PS4 Move): it tracks gravity with a complementary filter, computes the downward speed of the
  stick tip, and reports the exact sample time of the **peak of the swing** (or the impact spike in
  surface mode). Only the *detection* happens a sample later; the reported time is the peak time.
- The game does not judge on frame time. The song clock is a linear model on the same monotonic
  clock, drift-corrected against the audio playback position, and each hit's timestamp is
  converted into song time directly. Audio output latency is set to 10 ms in the project settings;
  V-Sync is off by default.
- Don/Ka zones come from the latest camera frame (typically 8 ms old at 125 fps); the hand is
  already at the drum when the peak happens, so the zone is stable.
- The results screen shows mean and spread of your hit errors and can apply the mean as the input
  offset; the wizard has a dedicated metronome test for the same thing.

## Keyboard / menu controls

| Action | Keys | Move controller |
|--------|------|-----------------|
| Ka (left) / Don (left) / Don (right) / Ka (right) | D / F / J / K | drum |
| Menu select / back | Enter / Esc | Move or Trigger / Select or Circle |
| Menu navigation | arrows | Triangle (up), Cross (down), Square (left) |
| Pause | Esc | Start |

## Importing songs

Song select → *Import .osz / .osu* (or drop files on the window). Songs are stored in
`%APPDATA%\Godot\app_userdata\TaikoMove\songs` (the *Open songs folder* button opens it); you
can also copy song folders there and press *Rescan*.

## Troubleshooting

- *No controllers*: make sure they are paired and turned on (PS button). In Windows Bluetooth
  settings they appear as "Motion Controller". Battery level shows in the wizard.
- *No camera*: check the WinUSB driver (Zadig) and that no other program uses the camera.
- *Wrong Don/Ka*: re-run the drum zone step, lower the exposure until only the spheres are bright,
  and make sure the two hands use clearly different LED colors (Unlockables).
- *Double hits or missed hits*: run the sensitivity auto-calibration, or adjust *Swing threshold*
  and *Minimum peak* in Settings. Increase *Minimum time between hits* if you get doubles.
- *Everything feels late/early*: use the offset test in the wizard or the suggestion on the results
  screen. Keep V-Sync off; set a FPS limit only if the GPU is very loud.

## License

GPL-2.0-or-later. See `THIRD_PARTY.md` for the components used by the hardware extension.
