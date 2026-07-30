# GalaxyLink

Use a **Samsung Galaxy Tab S10 Ultra as a true second monitor** for a MacBook Pro.
GalaxyLink is a macOS menu-bar app that creates a virtual display (macOS extends
your desktop onto it exactly like a plugged-in monitor), captures it at 60 fps,
hardware-encodes it to H.264, and streams it to a browser page on the tablet —
over Wi-Fi or a USB cable. No app install on the tablet; any WebCodecs-capable
browser (current Chrome / Samsung Internet) works.

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
│ Tablet browser: WebSocket → WebCodecs VideoDecoder → canvas        │
│ Fullscreen + wake lock + auto-reconnect (single static page / PWA) │
└────────────────────────────────────────────────────────────────────┘
```

## Requirements

- macOS 14 or later (Apple Silicon or Intel with H.264 hardware encoding).
- Galaxy Tab S10 Ultra — or any device with a WebCodecs-capable browser.
- Same Wi-Fi network as the Mac, or a USB cable (see USB mode).
- Swift toolchain to build (`swift build`); no third-party dependencies.

## Build & run

```bash
swift run -c release GalaxyLink        # menu-bar app (⬒ icon)
```

Other entry points:

```bash
swift run GalaxyLink --serve           # headless: start streaming with defaults, no UI
swift run GalaxyLink --probe-display   # verify the virtual display can be created
swift run GalaxyLink --probe-capture   # verify screen capture works (needs permission)
```

From the ⬒ menu: **Start Streaming**, then open the shown URL on the tablet
(or scan the QR code). Pick a resolution preset under **Resolution**:

- **Best (2960×1848 HiDPI)** — native tablet panel, sharp "Retina" UI (default)
- **Balanced (2560×1600 HiDPI)** — fewer pixels to encode, lower latency/CPU
- **Compatibility (1480×924 1×)** — non-HiDPI fallback

## First-run permissions (macOS)

The first capture triggers the **Screen Recording** permission prompt for the
app that launched GalaxyLink (your terminal, or the app hosting your shell).
Grant it in **System Settings ▸ Privacy & Security ▸ Screen Recording**, then
start streaming again. Rebuilding the binary can occasionally invalidate the
grant — toggle it off/on there if capture stops working after a rebuild.

## Tablet setup — Wi-Fi

1. Mac menu bar ▸ ⬒ ▸ **Start Streaming**.
2. On the tablet, open the URL shown in the menu (e.g. `http://192.168.1.23:8080`)
   in Chrome or Samsung Internet — or scan the QR code.
3. Tap anywhere on the stream to go fullscreen.
4. Optional, nicer: Chrome ⋮ ▸ **Add to Home screen** installs GalaxyLink as a
   PWA — launching from the home screen gives fullscreen with zero browser chrome.

The page keeps the screen awake (wake lock) and auto-reconnects if the Mac app
restarts.

> **Wi-Fi requires a one-time browser flag.** WebCodecs is only available in
> "secure contexts" (HTTPS or localhost), and the Wi-Fi URL is plain HTTP over
> the network. On the tablet, open
> `chrome://flags/#unsafely-treat-insecure-origin-as-secure`, add the GalaxyLink
> URL (e.g. `http://192.168.1.23:8080`), set it to **Enabled**, and relaunch
> Chrome. Redo this if the Mac's IP changes. USB mode needs no flag, because
> `http://localhost:8080` is already a secure context.

## Tablet setup — USB (lowest latency)

One-time tablet setup:

1. Settings ▸ About tablet ▸ Software information ▸ tap **Build number** 7×.
2. Settings ▸ **Developer options** ▸ enable **USB debugging**.
3. On the Mac: `brew install android-platform-tools` (provides `adb`).

Then: connect the cable, accept the "Allow USB debugging" prompt on the tablet,
and choose **Enable USB Mode (adb)** from the ⬒ menu. Open
`http://localhost:8080` on the tablet. This tunnels both ports over the cable
(`adb reverse`), so it works with Wi-Fi off entirely.

## End-to-end checklist

Run after any pipeline change:

1. `swift test` passes.
2. `swift run GalaxyLink --probe-display` prints `PROBE OK`.
3. `swift run GalaxyLink --probe-capture` prints `PROBE OK` (grant Screen
   Recording on first run).
4. `swift run GalaxyLink --serve`, then open `http://localhost:8080` in Chrome
   **on the Mac**: the virtual display's desktop renders live (drag a window
   onto the "GalaxyLink" display in System Settings ▸ Displays to see motion).
5. Tablet over Wi-Fi: URL loads, fullscreen works, window dragging is smooth
   (~60 fps), screen stays awake.
6. Quit the Mac app: tablet shows "Reconnecting…"; relaunch: stream resumes
   without reloading the page.
7. USB: **Enable USB Mode**, then `http://localhost:8080` on the tablet works
   with Wi-Fi disabled.

## Known limitations

- **DRM video blanks while streaming.** While any screen-capture session is
  active, macOS blanks FairPlay/Widevine-protected video (Netflix, Apple TV+,
  etc.) on **all** displays — including the Mac's own screen, and regardless of
  the player app or capture filter (verified experimentally: excluding the app
  from the capture filter does not help). This affects every capture-based
  mirror, not just GalaxyLink. Workaround: stop streaming while watching
  (the tablet client auto-reconnects when you start again).
- **Display only** — tablet touch/S Pen does not control the Mac yet. The wire
  protocol reserves frame types `0x10+` for future input events.
- **Single client** at full quality; extra viewers share the same stream.
- **Private API**: the virtual display uses the private `CGVirtualDisplay`
  CoreGraphics API (the same one Deskreen/BetterDisplay use). A future macOS
  release could change it; all usage is isolated in
  `Sources/GalaxyLink/VirtualDisplay.swift`. Fallback if it ever breaks: a
  headless HDMI dongle + capturing that display.
- No audio, and no App Store distribution (the private API rules it out).

## Project docs

- Design spec: `docs/superpowers/specs/2026-07-28-galaxylink-design.md`
- Implementation plan: `docs/superpowers/plans/2026-07-28-galaxylink.md`
