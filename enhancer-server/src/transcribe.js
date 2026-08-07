/**
 * OpenAI Whisper proxy — used when the Mac app prefers localhost over direct API calls.
 * Requires OPENAI_API_KEY in the enhancer process environment.
 */
import { Buffer } from "node:buffer";

export async function transcribeWithWhisper({
  audioBuffer,
  filename = "audio.m4a",
  languageHint = "te",
  apiKey = process.env.OPENAI_API_KEY,
}) {
  if (!apiKey) {
    const err = new Error("OPENAI_API_KEY missing — set it before starting the enhancer");
    err.status = 401;
    throw err;
  }
  if (!audioBuffer || !audioBuffer.length) {
    const err = new Error("audio file required");
    err.status = 400;
    throw err;
  }

  const prompt =
    languageHint === "hi" || languageHint === "hi-IN"
      ? "Hindi and English mixed speech (Hinglish). Keep Hindi in Devanagari script."
      : languageHint === "en" || languageHint === "en-US"
        ? "English speech."
        : "Telugu and English mixed speech (Tanglish). Keep Telugu in Telugu script.";

  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");
  form.append("timestamp_granularities[]", "word");
  form.append("prompt", prompt);
  form.append("file", new Blob([audioBuffer], { type: "audio/m4a" }), filename);

  const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`Whisper API ${res.status}: ${text.slice(0, 280)}`);
    err.status = res.status;
    throw err;
  }
  const json = JSON.parse(text);
  const words = [];
  for (const w of json.words || []) {
    if (!w?.word) continue;
    words.push({
      text: String(w.word).trim(),
      startTime: Number(w.start) || 0,
      endTime: Math.max(Number(w.end) || 0, (Number(w.start) || 0) + 0.05),
    });
  }
  if (!words.length && Array.isArray(json.segments)) {
    for (const seg of json.segments) {
      for (const w of seg.words || []) {
        if (!w?.word) continue;
        words.push({
          text: String(w.word).trim(),
          startTime: Number(w.start) || 0,
          endTime: Math.max(Number(w.end) || 0, (Number(w.start) || 0) + 0.05),
        });
      }
    }
  }
  return {
    text: json.text || words.map((w) => w.text).join(" "),
    language: json.language || languageHint,
    words,
    source: "openai-whisper-1",
  };
}

/** Express raw-body helper for multipart-ish simple uploads (base64 JSON). */
export function decodeBase64Audio(b64) {
  return Buffer.from(String(b64 || ""), "base64");
}
