# GalaxyLink — Design

**Date:** 2026-07-28
**Status:** Approved by user

## Goal

Use a Samsung Galaxy Tab S10 Ultra as a true second monitor for a MacBook Pro:
macOS extends the desktop onto a virtual display, which is streamed live to the
tablet over Wi-Fi or USB. Display only — no touch/pen input back to the Mac
(the protocol leaves room to add it later).

## Decisions (user-confirmed)

- **Build it** as our own tool, not configure an existing one.
- **Tablet client:** browser page (fullscreen via Fullscreen API / PWA).
  Native Android app only if the browser hits a wall.
- **Connection:** Wi-Fi by default; USB as an optional low-latency mode.
- **Input:** display only for now.

## Architecture

```
┌────────────────────── macOS (GalaxyLink.app) ──────────────────────┐
│ CGVirtualDisplay → ScreenCaptureKit → VideoToolbox H.264 encoder   │
│        (virtual monitor)   (60fps capture)   (low-latency mode)    │
│                                   │                                │
│                     Embedded HTTP + WebSocket server               │
│                     (Network.framework, port 8080)                 │
└───────────────────────────────────┬────────────────────────────────┘
                    Wi-Fi (LAN)  or  USB (adb reverse tcp:8080)
┌───────────────────────────────────┴────────────────────────────────┐
│ Tablet browser: WebSocket → WebCodecs VideoDecoder → canvas        │
│ Fullscreen + wake lock + auto-reconnect (single static page / PWA) │
└────────────────────────────────────────────────────────────────────┘
```

### Virtual display

- Created with `CGVirtualDisplay` (private CoreGraphics API — same approach as
  Deskreen / BetterDisplay). macOS treats it as a real monitor: appears in
  System Settings → Displays, windows drag onto it.
- Geometry matches the Tab S10 Ultra panel: **2960×1848 (16:10)**, exposed as a
  **1480×924 HiDPI** mode so UI is sharp and normally sized. Additional modes
  (native 1×, lower resolutions) selectable in settings.
- **Risk:** private API may change in a future macOS release. Mitigation: all
  usage isolated in one small wrapper type (`VirtualDisplay`), so a break is a
  one-file fix or swap (e.g. to a headless-dongle mode).

### Capture and encode

- ScreenCaptureKit `SCStream` bound to the virtual display; 60 fps target,
  BGRA → NV12 pixel buffers.
- VideoToolbox `VTCompressionSession`, H.264, low-latency rate control
  (`kVTVideoEncoderSpecification_EnableLowLatencyRateControl`), default
  ~15 Mbps, keyframe on demand + periodic (~2 s).
- Requires the one-time **Screen Recording** TCC permission.

### Transport: WebSocket + WebCodecs

Chosen over WebRTC (huge dependency, ICE/SDP machinery useless on a LAN,
UDP won't traverse `adb reverse`) and MSE (200–500 ms buffering latency).

- Embedded server (Network.framework `NWListener`, no third-party deps):
  - `GET /` and static assets → the client page.
  - `GET /ws` → WebSocket carrying a small binary protocol.
- **Binary frame protocol** (all little-endian):
  - `0x01 CONFIG` — JSON: codec string (`avc1.…`), coded width/height, fps.
    Sent on connect and whenever the encoder restarts.
  - `0x02 VIDEO` — `[u8 type][u8 flags(bit0=keyframe)][u64 timestampMicros][payload: H.264 Annex-B]`.
  - Reserved `0x10+` for future input events (tablet → Mac).
- **Backpressure:** single-client; if the socket send buffer exceeds a
  threshold, drop delta frames and force a keyframe when it drains.

### Tablet client

- One static HTML/JS page, no build step. WebSocket → `VideoDecoder`
  (WebCodecs) → `canvas` (paint on decode, no queueing).
- Fullscreen button (Fullscreen API); PWA manifest with `display: fullscreen`
  for chrome-free installed mode; Screen Wake Lock API; auto-reconnect with
  backoff.
- Requires a WebCodecs-capable browser (current Chrome / Samsung Internet).

### USB mode

Same server, same URL, different route: `adb reverse tcp:8080 tcp:8080`
makes `http://localhost:8080` on the tablet reach the Mac over the cable.
The app ships a helper that detects `adb` + an attached device and runs the
command; docs cover the one-time USB-debugging enable on the tablet.

### Mac app UX

Menu-bar app (SwiftUI): Start/Stop streaming, connection URL + QR code,
resolution/fps/bitrate settings, USB mode status. No Dock icon.

## Testing

- Unit tests: binary protocol encode/decode, backpressure policy, settings.
- The capture/encode/display pipeline is verified end-to-end on the real
  tablet (checklist in README), since virtual displays and TCC permissions
  don't exercise well under CI.

## Build order

1. **Pipeline proof:** virtual display → capture → encode → WebSocket →
   tablet page renders the desktop.
2. **Polish:** fullscreen/PWA, wake lock, auto-reconnect, QR code, settings UI.
3. **USB helper** + docs.

## Out of scope (for now)

Touch/S Pen input, audio, multiple clients, HEVC/AV1, App Store distribution
(private API rules it out anyway).
