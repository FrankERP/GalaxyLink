# GalaxyLink

**Use an Android tablet as a real second monitor for your Mac** — over Wi-Fi or
a USB cable, with nothing to install on the tablet.

GalaxyLink is a macOS menu-bar app that creates a virtual display (macOS
extends your desktop onto it exactly like a plugged-in monitor), captures it at
60 fps, hardware-encodes it to H.264, and streams it to a browser page on the
tablet. Built and tuned for the Samsung Galaxy Tab S10 Ultra, but any device
with a WebCodecs-capable browser (current Chrome / Samsung Internet) works.

- **True display extension** — a real HiDPI ("Retina") monitor in macOS
  Display settings, not a mirror.
- **Sharp and smooth** — 2960×1848 @ 60 fps, hardware encode/decode end to
  end, WebGL rendering on the tablet.
- **Zero-install client** — the tablet just opens a URL (installable as a
  fullscreen PWA). QR code in the menu for easy pairing.
- **Wi-Fi or USB** — USB (`adb reverse`) gives the lowest, most consistent
  latency.
- **No third-party dependencies** — Swift + Network.framework +
  ScreenCaptureKit + VideoToolbox, one static HTML/JS client.

```
┌────────────────────── macOS (GalaxyLink.app) ──────────────────────┐
│ CGVirtualDisplay → ScreenCaptureKit → VideoToolbox H.264 encoder   │
│        (virtual monitor)   (60fps capture)   (low-latency mode)    │
│                                   │                                │
│                     Embedded HTTP + WebSocket server               │
│                     (ports 8080 http / 8081 ws)                    │
└───────────────────────────────────┬────────────────────────────────┘
                    Wi-Fi (LAN)  or  USB (adb reverse)
┌───────────────────────────────────┴────────────────────────────────┐
│ Tablet browser: WebSocket → WebCodecs VideoDecoder → WebGL canvas  │
│ Fullscreen + wake lock + auto-reconnect (single static page / PWA) │
└────────────────────────────────────────────────────────────────────┘
```

## Requirements

- **Mac**: macOS 14 or later; Apple Silicon or Intel with H.264 hardware
  encoding. Xcode Command Line Tools (for building): `xcode-select --install`.
- **Tablet**: any Android tablet (or other device) with a WebCodecs-capable
  browser — current Chrome or Samsung Internet. Default resolution presets
  target the Galaxy Tab S10 Ultra's 2960×1848 panel; for a different device,
  adjust `Sources/GalaxyLink/DisplayPreset.swift` (PRs welcome for a custom
  resolution UI).
- Same Wi-Fi network as the Mac, **or** a USB cable (see USB mode; also needs
  `adb`: `brew install android-platform-tools`).

## Install

```bash
git clone https://github.com/FrankERP/GalaxyLink.git
cd GalaxyLink
./scripts/make_app.sh
cp -R dist/GalaxyLink.app /Applications/
open /Applications/GalaxyLink.app
```

A **⬒** icon appears in the menu bar. Optional: add GalaxyLink to
**System Settings ▸ General ▸ Login Items** so it starts at login.

**First run:** the first *Start Streaming* triggers the macOS
**Screen Recording** permission prompt. Grant it in System Settings ▸ Privacy
& Security ▸ Screen Recording, then start streaming again. The app is ad-hoc
signed by `make_app.sh`, so the grant survives rebuilds.

## Usage

1. Menu bar ▸ **⬒ ▸ Start Streaming**. A "GalaxyLink" display appears in
   System Settings ▸ Displays — arrange it like any monitor.
2. On the tablet, open the URL shown in the menu (click to copy) or scan the
   QR code.
3. Tap anywhere on the stream for fullscreen.
4. Nicer: Chrome ⋮ ▸ **Add to Home screen** installs it as a PWA — launching
   from that icon is fullscreen from the first frame.

Pick a resolution preset under **⬒ ▸ Resolution**:

| Preset | Pixels | UI looks like | Use when |
|---|---|---|---|
| Best (default) | 2960×1848 | 1480×924 @2x | Native sharpness |
| Balanced | 2560×1600 | 1280×800 @2x | Lower latency / older tablets |
| Compatibility | 1480×924 | 1480×924 @1x | Fallback |

### Wi-Fi mode

Works out of the box **except** for one browser flag: WebCodecs requires a
"secure context", and the Wi-Fi URL is plain HTTP. On the tablet, open
`chrome://flags/#unsafely-treat-insecure-origin-as-secure`, add the GalaxyLink
URL (e.g. `http://192.168.1.23:8080`), set it to **Enabled**, relaunch Chrome.
Redo this if the Mac's IP changes. (USB mode needs no flag — `localhost` is
already a secure context.)

### USB mode (lowest latency)

One-time tablet setup: Settings ▸ About tablet ▸ Software information ▸ tap
**Build number** 7× to enable Developer options, then Developer options ▸
**USB debugging** on. On the Mac: `brew install android-platform-tools`.

Then: connect the cable (USB mode "File transfer", accept the debugging
prompt), click **⬒ ▸ Enable USB Mode (adb)**, and open
`http://localhost:8080` on the tablet. Works with Wi-Fi off entirely.
Re-run *Enable USB Mode* after re-plugging the cable.

## Troubleshooting

- **"WebCodecs needs a secure context"** → you're on Wi-Fi without the Chrome
  flag above, or use USB mode instead.
- **Stutter or artifacts** → append `?stats=1` to the URL for a live overlay
  (received / decoded / painted fps + decode queue). Low `recv` = network or
  encoder; low `paint` = tablet rendering; try the Balanced preset.
- **Black screen on connect** → should not happen (the server re-encodes the
  last frame for late joiners); check that the Mac app shows *streaming*.
- **Capture permission loops** → System Settings ▸ Privacy & Security ▸
  Screen Recording, toggle GalaxyLink off and on.
- Developer probes: `swift run GalaxyLink --probe-display`,
  `--probe-capture`, `--probe-api`, and
  `swift run GalaxyLink --serve [--preset balanced|compat]` for headless runs.

## Known limitations

- **DRM video (Netflix, Apple TV+…) blanks on all displays while streaming.**
  macOS blanks protected video whenever any screen-capture session is active —
  on every screen, regardless of player app or capture filter (verified:
  excluding the app from the capture filter does not help). This affects every
  capture-based mirror. Workaround: *Stop Streaming* while watching; the
  tablet auto-reconnects afterwards.
- **Display only** — tablet touch / S Pen does not control the Mac (yet); the
  wire protocol reserves frame types `0x10+` for future input events.
- **Private API**: the virtual display uses the private `CGVirtualDisplay`
  CoreGraphics API (same as Deskreen / BetterDisplay). A future macOS release
  could change it; all usage is isolated in
  `Sources/GalaxyLink/VirtualDisplay.swift`. This also rules out App Store
  distribution.
- Single client at full quality; no audio.

## How it works / contributing

The design spec and implementation plan live in
[docs/superpowers/](docs/superpowers/). Interesting bits:

- `VirtualDisplay.swift` — private-API wrapper, including the trick of
  selecting the hidden Retina mode
  (`kCGDisplayShowDuplicateLowResolutionModes` +
  `CGConfigureDisplayWithDisplayMode`); without it macOS silently renders the
  virtual display at 1x.
- `H264Encoder.swift` — VideoToolbox low-latency rate control, Annex-B with
  in-band SPS/PPS so the WebCodecs client needs no `description`.
- `Resources/web/client.js` — WebCodecs → WebGL with rAF-paced
  latest-frame-wins rendering and deferred `VideoFrame.close()` (avoids GPU
  driver glitches on Android).

`swift test` runs the unit suite (protocol, backpressure, servers, encoder).
Issues and PRs welcome — custom resolution presets, touch input, and audio are
the obvious next features.

## License

[MIT](LICENSE)
