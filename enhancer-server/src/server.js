import cors from "cors";
import express from "express";
import path from "node:path";
import { enhanceWithCursor } from "./enhance.js";
import { LIBRARIES_ROOT, loadLibraries } from "./libraries.js";
import { decodeBase64Audio, transcribeWithWhisper } from "./transcribe.js";

const app = express();
const PORT = Number(process.env.PORT || 8787);

app.use(cors());
app.use(express.json({ limit: "40mb" }));

// Serve asset libraries so the Swift app / previews can fetch files.
app.use("/libraries", express.static(LIBRARIES_ROOT));

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    hasCursorKey: Boolean(process.env.CURSOR_API_KEY),
    hasOpenAIKey: Boolean(process.env.OPENAI_API_KEY),
    model: "composer-2.5",
    sdk: "@cursor/sdk",
    whisper: "whisper-1",
  });
});

app.get("/libraries", (_req, res) => {
  res.json(loadLibraries());
});

/**
 * POST /transcribe
 * body: { audioBase64: string, filename?: string, languageHint?: "te"|"hi"|"en" }
 * → { text, words: [{text,startTime,endTime}], source }
 *
 * Telugu is not in Apple Dictation — Whisper handles TE+EN code-switch.
 */
app.post("/transcribe", async (req, res) => {
  try {
    const { audioBase64, filename, languageHint } = req.body || {};
    const audioBuffer = decodeBase64Audio(audioBase64);
    const result = await transcribeWithWhisper({
      audioBuffer,
      filename: filename || "audio.m4a",
      languageHint: languageHint || "te",
    });
    res.json(result);
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || String(error) });
  }
});

/**
 * POST /enhance
 * body: { captions: [{text,startTime,endTime}], duration: number, forceHeuristic?: boolean }
 */
app.post("/enhance", async (req, res) => {
  try {
    const { captions, duration, forceHeuristic, videoSize, language, packId, brandKit, safeZone } = req.body || {};
    if (!Array.isArray(captions)) {
      res.status(400).json({ error: "captions array required" });
      return;
    }
    const plan = await enhanceWithCursor({
      captions,
      duration,
      forceHeuristic: Boolean(forceHeuristic),
      videoSize: videoSize && videoSize.width && videoSize.height
        ? { width: Number(videoSize.width), height: Number(videoSize.height) }
        : null,
      language: language || "en-US",
      packId: packId || null,
      brandKit: brandKit || null,
      safeZone: safeZone || null,
    });
    res.json(plan);
  } catch (error) {
    res.status(500).json({ error: error.message || String(error) });
  }
});

app.get("/", (_req, res) => {
  res.type("html").send(`<!doctype html>
<html><head><title>CaptionStudio Enhancer</title>
<style>
  body{font-family:ui-sans-serif,system-ui;background:#0b1214;color:#e8fff8;padding:40px;line-height:1.5}
  code{background:#122025;padding:2px 6px;border-radius:6px}
  a{color:#33f2cf}
</style></head>
<body>
  <h1>CaptionStudio Enhancer</h1>
  <p>Uses <code>@cursor/sdk</code> (model <code>composer-2.5</code>) to decide where to place stylish text, GIFs, PNGs, and SFX from <code>/libraries</code>.</p>
  <ul>
    <li><a href="/health">/health</a></li>
    <li><a href="/libraries">/libraries</a> (JSON catalogs)</li>
    <li>POST <code>/enhance</code> with caption timeline</li>
    <li>POST <code>/transcribe</code> — Whisper (needs <code>OPENAI_API_KEY</code>)</li>
  </ul>
</body></html>`);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`CaptionStudio enhancer on http://127.0.0.1:${PORT}`);
  console.log(`Libraries: ${LIBRARIES_ROOT}`);
  console.log(`CURSOR_API_KEY: ${process.env.CURSOR_API_KEY ? "set" : "missing (heuristic fallback)"}`);
  console.log(`OPENAI_API_KEY: ${process.env.OPENAI_API_KEY ? "set (Whisper /transcribe)" : "missing (Telugu captions need key in app Brand Kit)"}`);
});
