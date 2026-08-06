import cors from "cors";
import express from "express";
import path from "node:path";
import { enhanceWithCursor } from "./enhance.js";
import { LIBRARIES_ROOT, loadLibraries } from "./libraries.js";

const app = express();
const PORT = Number(process.env.PORT || 8787);

app.use(cors());
app.use(express.json({ limit: "2mb" }));

// Serve asset libraries so the Swift app / previews can fetch files.
app.use("/libraries", express.static(LIBRARIES_ROOT));

app.get("/health", (_req, res) => {
  res.json({
    ok: true,
    hasCursorKey: Boolean(process.env.CURSOR_API_KEY),
    model: "composer-2.5",
    sdk: "@cursor/sdk",
  });
});

app.get("/libraries", (_req, res) => {
  res.json(loadLibraries());
});

/**
 * POST /enhance
 * body: { captions: [{text,startTime,endTime}], duration: number, forceHeuristic?: boolean }
 */
app.post("/enhance", async (req, res) => {
  try {
    const { captions, duration, forceHeuristic, videoSize } = req.body || {};
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
  </ul>
</body></html>`);
});

app.listen(PORT, "0.0.0.0", () => {
  console.log(`CaptionStudio enhancer on http://127.0.0.1:${PORT}`);
  console.log(`Libraries: ${LIBRARIES_ROOT}`);
  console.log(`CURSOR_API_KEY: ${process.env.CURSOR_API_KEY ? "set" : "missing (heuristic fallback)"}`);
});
