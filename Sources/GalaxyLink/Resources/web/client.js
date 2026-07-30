"use strict";

const canvas = document.getElementById("screen");
const ctx = canvas.getContext("2d", { alpha: false, desynchronized: true });
const overlay = document.getElementById("overlay");
const statusEl = document.getElementById("status");
const hint = document.getElementById("hint");

let ws = null;
let decoder = null;
let seenKeyframe = false;
let wakeLock = null;

// Diagnostics overlay, enabled with ?stats=1
const statsEl = document.getElementById("stats");
const counters = { recv: 0, dec: 0, paint: 0 };
if (new URLSearchParams(location.search).get("stats") === "1") {
  statsEl.hidden = false;
  setInterval(() => {
    const q = decoder && decoder.state === "configured" ? decoder.decodeQueueSize : "-";
    statsEl.textContent =
      `recv ${counters.recv}/s  dec ${counters.dec}/s  paint ${counters.paint}/s  queue ${q}`;
    counters.recv = counters.dec = counters.paint = 0;
  }, 1000);
}

function setStatus(text) {
  statusEl.textContent = text;
  overlay.classList.remove("hidden");
}

function hideOverlay() {
  overlay.classList.add("hidden");
}

// Latest-frame-wins rendering, paced by requestAnimationFrame: if decode
// runs ahead of the display, stale frames are dropped instead of queued,
// keeping latency flat and motion smooth.
let pendingFrame = null;
let renderScheduled = false;

function paint(frame) {
  counters.dec++;
  if (pendingFrame) pendingFrame.close();
  pendingFrame = frame;
  if (renderScheduled) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    const f = pendingFrame;
    pendingFrame = null;
    if (!f) return;
    if (canvas.width !== f.displayWidth || canvas.height !== f.displayHeight) {
      canvas.width = f.displayWidth;
      canvas.height = f.displayHeight;
    }
    ctx.drawImage(f, 0, 0);
    f.close();
    counters.paint++;
  });
}

function setupDecoder(cfg) {
  if (decoder) { try { decoder.close(); } catch (_) {} }
  seenKeyframe = false;
  decoder = new VideoDecoder({
    output: paint,
    error: (e) => { console.error("decoder error", e); reconnect(); },
  });
  // No `description` => Annex-B mode; keyframes carry SPS/PPS in-band.
  decoder.configure({ codec: cfg.codec, optimizeForLatency: true });
  hideOverlay();
  updateHint();
}

function handleMessage(buffer) {
  const view = new DataView(buffer);
  const type = view.getUint8(0);
  if (type === 0x01) {
    const cfg = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 1)));
    setupDecoder(cfg);
  } else if (type === 0x02 && decoder && decoder.state === "configured") {
    counters.recv++;
    const isKey = (view.getUint8(1) & 1) === 1;
    if (!seenKeyframe && !isKey) return;
    seenKeyframe = true;
    const timestamp = Number(view.getBigUint64(2, true));
    decoder.decode(new EncodedVideoChunk({
      type: isKey ? "key" : "delta",
      timestamp,
      data: new Uint8Array(buffer, 10),
    }));
  }
}

let reconnectTimer = null;
function reconnect() {
  if (reconnectTimer) return;
  if (ws) { try { ws.close(); } catch (_) {} ws = null; }
  setStatus("Reconnecting…");
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 1000);
}

function connect() {
  if (!("VideoDecoder" in window)) {
    if (!window.isSecureContext) {
      setStatus("WebCodecs needs a secure context, and plain http:// over the network is not one. " +
                "Either use USB mode (open http://localhost:8080 via adb reverse), or in Chrome enable " +
                "chrome://flags/#unsafely-treat-insecure-origin-as-secure for " + location.origin + " and relaunch.");
    } else {
      setStatus("This browser lacks WebCodecs. Use Chrome or Samsung Internet.");
    }
    return;
  }
  ws = new WebSocket(`ws://${location.hostname}:8081`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => handleMessage(e.data);
  ws.onclose = reconnect;
  ws.onerror = reconnect;
}

function updateHint() {
  // Show the hint whenever the stream is up but we're not fullscreen.
  hint.hidden = !!document.fullscreenElement || !decoder || decoder.state !== "configured";
}

async function enterFullscreen() {
  if (document.fullscreenElement) return;
  try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }); } catch (_) {}
  try { if (screen.orientation && screen.orientation.lock) await screen.orientation.lock("landscape"); } catch (_) {}
}

document.addEventListener("click", enterFullscreen);
document.addEventListener("fullscreenchange", updateHint);

async function acquireWakeLock() {
  try { wakeLock = await navigator.wakeLock.request("screen"); } catch (_) {}
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") { acquireWakeLock(); if (!ws || ws.readyState > 1) reconnect(); }
});

acquireWakeLock();
connect();
