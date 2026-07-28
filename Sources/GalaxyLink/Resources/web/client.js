"use strict";

const canvas = document.getElementById("screen");
const ctx = canvas.getContext("2d", { alpha: false, desynchronized: true });
const overlay = document.getElementById("overlay");
const statusEl = document.getElementById("status");
const goBtn = document.getElementById("go");

let ws = null;
let decoder = null;
let seenKeyframe = false;
let wakeLock = null;

function setStatus(text) {
  statusEl.textContent = text;
  overlay.classList.remove("hidden");
}

function hideOverlay() {
  overlay.classList.add("hidden");
}

function paint(frame) {
  if (canvas.width !== frame.displayWidth || canvas.height !== frame.displayHeight) {
    canvas.width = frame.displayWidth;
    canvas.height = frame.displayHeight;
  }
  ctx.drawImage(frame, 0, 0);
  frame.close();
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
  goBtn.hidden = false;
}

function handleMessage(buffer) {
  const view = new DataView(buffer);
  const type = view.getUint8(0);
  if (type === 0x01) {
    const cfg = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 1)));
    setupDecoder(cfg);
  } else if (type === 0x02 && decoder && decoder.state === "configured") {
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
    setStatus("This browser lacks WebCodecs. Use Chrome or Samsung Internet.");
    return;
  }
  ws = new WebSocket(`ws://${location.hostname}:8081`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => handleMessage(e.data);
  ws.onclose = reconnect;
  ws.onerror = reconnect;
}

goBtn.addEventListener("click", async () => {
  try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }); } catch (_) {}
  try { if (screen.orientation && screen.orientation.lock) await screen.orientation.lock("landscape"); } catch (_) {}
  hideOverlay();
});

async function acquireWakeLock() {
  try { wakeLock = await navigator.wakeLock.request("screen"); } catch (_) {}
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") { acquireWakeLock(); if (!ws || ws.readyState > 1) reconnect(); }
});

acquireWakeLock();
connect();
