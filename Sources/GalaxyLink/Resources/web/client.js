"use strict";

const canvas = document.getElementById("screen");

// GPU renderer: WebGL texture upload is far faster than 2D drawImage for
// large VideoFrames on Android. Falls back to 2D where WebGL is unavailable.
function createRenderer(cv) {
  const gl = cv.getContext("webgl", { alpha: false, antialias: false });
  if (!gl) {
    const c2d = cv.getContext("2d", { alpha: false, desynchronized: true });
    return {
      draw(frame) {
        if (cv.width !== frame.displayWidth || cv.height !== frame.displayHeight) {
          cv.width = frame.displayWidth;
          cv.height = frame.displayHeight;
        }
        c2d.drawImage(frame, 0, 0);
      },
    };
  }
  const vsSrc = "attribute vec2 pos; varying vec2 uv;" +
    "void main(){ uv = vec2((pos.x+1.0)*0.5, (1.0-pos.y)*0.5); gl_Position = vec4(pos,0.0,1.0); }";
  const fsSrc = "precision mediump float; varying vec2 uv; uniform sampler2D tex;" +
    "void main(){ gl_FragColor = texture2D(tex, uv); }";
  const program = gl.createProgram();
  for (const [type, src] of [[gl.VERTEX_SHADER, vsSrc], [gl.FRAGMENT_SHADER, fsSrc]]) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, src);
    gl.compileShader(shader);
    gl.attachShader(program, shader);
  }
  gl.linkProgram(program);
  gl.useProgram(program);
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const posLoc = gl.getAttribLocation(program, "pos");
  gl.enableVertexAttribArray(posLoc);
  gl.vertexAttribPointer(posLoc, 2, gl.FLOAT, false, 0, 0);
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return {
    draw(frame) {
      if (cv.width !== frame.displayWidth || cv.height !== frame.displayHeight) {
        cv.width = frame.displayWidth;
        cv.height = frame.displayHeight;
        gl.viewport(0, 0, cv.width, cv.height);
      }
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, frame);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    },
  };
}

const renderer = createRenderer(canvas);
const overlay = document.getElementById("overlay");
const statusEl = document.getElementById("status");
const detailEl = document.getElementById("detail");
const hint = document.getElementById("hint");
const a2hs = document.getElementById("a2hs");
const A2HS_KEY = "galaxylink.homescreenHint";
let a2hsTimer = null;
let a2hsOffered = false;

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

function setStatus(text, detail) {
  statusEl.textContent = text;
  detailEl.textContent = detail || "";
  overlay.classList.remove("hidden");
}

function hideOverlay() {
  overlay.classList.add("hidden");
}

// Latest-frame-wins rendering, paced by requestAnimationFrame: if decode
// runs ahead of the display, stale frames are dropped instead of queued,
// keeping latency flat and motion smooth.
let pendingFrame = null;
let inFlightFrame = null; // frame the GPU consumed last draw; closed one cycle later
let renderScheduled = false;

function paint(frame) {
  counters.dec++;
  maybeOfferA2hs();
  if (pendingFrame) pendingFrame.close();
  pendingFrame = frame;
  if (renderScheduled) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    const f = pendingFrame;
    pendingFrame = null;
    if (!f) return;
    renderer.draw(f);
    // Closing immediately can invalidate the frame before the GPU has
    // sampled it on some Android drivers (occasional garbage pixels), so
    // keep it alive until the next draw completes.
    if (inFlightFrame) inFlightFrame.close();
    inFlightFrame = f;
    counters.paint++;
  });
}

function setupDecoder(cfg) {
  if (decoder) { try { decoder.close(); } catch (_) {} }
  if (pendingFrame) { pendingFrame.close(); pendingFrame = null; }
  if (inFlightFrame) { inFlightFrame.close(); inFlightFrame = null; }
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
  setStatus("Looking for your Mac…");
  reconnectTimer = setTimeout(() => { reconnectTimer = null; connect(); }, 1000);
}

function connect() {
  if (!("VideoDecoder" in window)) {
    if (!window.isSecureContext) {
      setStatus("This tablet needs a trusted connection.", "Use a cable.");
    } else {
      setStatus("This browser cannot show the display. Use Chrome or Samsung Internet.");
    }
    return;
  }
  setStatus("Waking the display…");
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

function dismissA2hs() {
  a2hs.hidden = true;
  if (a2hsTimer) {
    clearTimeout(a2hsTimer);
    a2hsTimer = null;
  }
}

function maybeOfferA2hs() {
  if (a2hsOffered) return;
  a2hsOffered = true;
  try {
    if (localStorage.getItem(A2HS_KEY)) return;
  } catch (_) {}
  const installed = window.matchMedia("(display-mode: standalone), (display-mode: fullscreen)").matches;
  try { localStorage.setItem(A2HS_KEY, "1"); } catch (_) {}
  if (installed) return;
  a2hs.hidden = false;
  a2hsTimer = setTimeout(dismissA2hs, 5000);
}

async function enterFullscreen() {
  if (document.fullscreenElement) return;
  try { await document.documentElement.requestFullscreen({ navigationUI: "hide" }); } catch (_) {}
  try { if (screen.orientation && screen.orientation.lock) await screen.orientation.lock("landscape"); } catch (_) {}
}

document.addEventListener("click", () => {
  dismissA2hs();
  enterFullscreen();
});
document.addEventListener("fullscreenchange", updateHint);

async function acquireWakeLock() {
  try { wakeLock = await navigator.wakeLock.request("screen"); } catch (_) {}
}
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") { acquireWakeLock(); if (!ws || ws.readyState > 1) reconnect(); }
});

acquireWakeLock();
connect();
