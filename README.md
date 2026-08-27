# GalaxyLink

**Use an Android tablet as a real second monitor for your Mac.** Plug in a USB
cable; nothing to install on the tablet.

GalaxyLink is a macOS menu-bar app that creates a virtual display (macOS
extends your desktop onto it exactly like a plugged-in monitor), captures it at
60 fps, hardware-encodes it to H.264, and streams it to a browser page on the
tablet. Built and tuned for the Samsung Galaxy Tab S10 Ultra, but any device
with a WebCodecs-capable browser (current Chrome / Samsung Internet) works.

- **True display extension** — a real HiDPI ("Retina") monitor in macOS
  Display settings, not a mirror.
- **Sharp and smooth** — 2960×1848 @ 60 fps, hardware encode/decode end to
  end, WebGL rendering on the tablet.
- **Zero-install client** — the tablet opens `http://localhost:8080`
  (installable as a fullscreen PWA).
- **USB** — **Use a cable** on the pairing card, then `http://localhost:8080`
  on the tablet. Same Wi-Fi is collapsed there, not the path.
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
                    Wi-Fi (LAN)  or  Use a cable
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
- A USB cable. USB debugging on the tablet, and `adb` on the Mac
  (`brew install android-platform-tools`). Same Wi-Fi is optional and is not
  the first-run path.

## Install

```bash
git clone https://github.com/FrankERP/GalaxyLink.git
cd GalaxyLink
./scripts/make_app.sh
cp -R dist/GalaxyLink.app /Applications/
open /Applications/GalaxyLink.app
```

`make_app.sh` ad-hoc signs the app so the Screen Recording grant survives
rebuilds. A **⬒** icon appears in the menu bar. Optional: add GalaxyLink to
**System Settings ▸ General ▸ Login Items** so it starts at login.

## Usage

On first launch the pairing card opens (window title **GalaxyLink**). HTTP
and WebSocket listeners are already up, so the tablet can load the page
before capture starts. The card is also **Show pairing** in the menu later.

What you see:

- **Your second screen** (once)
- **Plug in the tablet.**
- **Use a cable** (primary)
- copyable `http://localhost:8080`
- If Screen Recording is missing: **GalaxyLink needs Screen Recording** and
  **Open Settings** on that same card
- **Start** (secondary)
- **Same Wi-Fi** collapsed — not the path.

One-time tablet setup: Settings ▸ About tablet ▸ Software information ▸ tap
**Build number** 7×, then Developer options ▸ **USB debugging** on. On the
Mac: `brew install android-platform-tools`.

1. Plug in the tablet (USB file transfer; accept the debugging prompt).
2. **Use a cable.** Success is **Cable ready.** on the card, not a modal. If
   nothing is attached: **No tablet. Plug in, turn on USB debugging, try
   again.** If `adb` is missing: **adb not found**.
3. On the tablet, open `http://localhost:8080`. Overlay: **Waking the
   display…**
4. **Start.** A GalaxyLink display appears in System Settings ▸ Displays —
   arrange it like any monitor. The pairing card returns on the next launch
   until this first successful Start; dismissing it does not skip first-run.
5. Tap for fullscreen. Once, if it is not already installed: **Add to Home
   screen for a real monitor**.

Re-run **Use a cable** after re-plugging the cable.

After that first Start, the menu is **GalaxyLink · Off** / **On**, **Start**
/ **Stop**, **Show pairing**, **Sharp** (default) / **Balanced** /
**Compatible**, **Use a cable**, **Quit**.

If the tablet overlay instead says **This tablet needs a trusted
connection.** / **Plug this tablet into the Mac.**, it opened a LAN URL.
Plug the tablet into the Mac and use `http://localhost:8080`. Reconnect
copy is **Looking for your Mac…**

## Troubleshooting

- **"This tablet needs a trusted connection."** → the tablet is not on
  localhost (plain LAN HTTP is not a secure context). Cable +
  `http://localhost:8080`.
- **"Looking for your Mac…"** → stream is not up, or the cable dropped.
  **Start**, and **Use a cable** again after re-plugging.
- **Stutter or artifacts** → append `?stats=1` to the URL for a live overlay
  (received / decoded / painted fps + decode queue). Low `recv` = network or
  encoder; low `paint` = tablet rendering; try **Balanced**.
- **Black screen on connect** → should not happen (the server re-encodes the
  last frame for late joiners); check that the menu shows **GalaxyLink · On**.
- **Capture permission loops** → pairing card **Open Settings**, or System
  Settings ▸ Privacy & Security ▸ Screen Recording, toggle GalaxyLink off
  and on.
- Developer probes: `swift run GalaxyLink --probe-display`,
  `--probe-capture`, `--probe-api`, and
  `swift run GalaxyLink --serve [--preset balanced|compat]` for headless runs.

## Known limitations

- **DRM video (Netflix, Apple TV+…) blanks on all displays while streaming.**
  macOS blanks protected video whenever any screen-capture session is active —
  on every screen, regardless of player app or capture filter (verified:
  excluding the app from the capture filter does not help). This affects every
  capture-based mirror. Workaround: **Stop** while watching; the tablet
  auto-reconnects afterwards.
- **Display only** — tablet touch / S Pen does not control the Mac (yet); the
  wire protocol reserves frame types `0x10+` for future input events.
- **Private API**: the virtual display uses the private `CGVirtualDisplay`
  CoreGraphics API (same as Deskreen / BetterDisplay). A future macOS release
  could change it; all usage is isolated in
  `Sources/GalaxyLink/VirtualDisplay.swift`. This also rules out App Store
  distribution.
- **Ad-hoc signing** via `./scripts/make_app.sh`. There is no notarized
  download.
- Single client at full quality; no audio.
- LAN HTTP is not a secure context, so Wi-Fi still needs
  `chrome://flags/#unsafely-treat-insecure-origin-as-secure`; the product path
  is a cable.

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
