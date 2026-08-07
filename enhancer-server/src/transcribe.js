/**
 * OpenAI Whisper proxy — Telugu must force language=te.
 * Auto-detect often returns Kannada for Telugu audio (related Dravidian scripts).
 */
import { Buffer } from "node:buffer";

function promptFor(languageHint, strongerTeluguBias = false) {
  if (languageHint === "hi" || languageHint === "hi-IN") {
    return "नमस्ते — हिन्दी और English mixed (Hinglish). Hindi in Devanagari; English words in Latin.";
  }
  if (languageHint === "en" || languageHint === "en-US") {
    return "English speech with clear word breaks.";
  }
  if (strongerTeluguBias) {
    return (
      "నమస్కారం ఇది తెలుగు వీడియో. Telugu script only (తెలుగు) — NOT Kannada (ಕನ್ನಡ). " +
      "English words stay in English Latin letters: subscribe, follow, wow, video."
    );
  }
  return (
    "నమస్కారం — తెలుగు మరియు English mixed (Tanglish). " +
    "Write Telugu words in Telugu script (తెలుగు), never Kannada. " +
    "Keep English loanwords in Latin script."
  );
}

function languageCode(languageHint) {
  if (languageHint === "hi" || languageHint === "hi-IN") return "hi";
  if (languageHint === "en" || languageHint === "en-US") return "en";
  return "te";
}

function scriptOf(text) {
  let te = 0,
    kn = 0,
    la = 0;
  for (const ch of String(text || "")) {
    const c = ch.codePointAt(0);
    if (c >= 0x0c00 && c <= 0x0c7f) te += 1;
    else if (c >= 0x0c80 && c <= 0x0cff) kn += 1;
    else if ((c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a)) la += 1;
  }
  if (te >= kn && te > 0) return "te";
  if (kn > te) return "kn";
  if (la > 0) return "la";
  return "other";
}

function isKannadaHeavy(words) {
  let te = 0,
    kn = 0;
  for (const w of words) {
    const s = scriptOf(w.text);
    if (s === "te") te += 1;
    if (s === "kn") kn += 1;
  }
  const indic = te + kn;
  if (indic < 3) return kn > 0 && te === 0;
  return kn > te;
}

async function whisperOnce({
  audioBuffer,
  filename,
  apiKey,
  languageHint,
  strongerTeluguBias = false,
}) {
  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");
  form.append("timestamp_granularities[]", "word");
  form.append("temperature", "0");
  form.append("language", languageCode(languageHint));
  form.append("prompt", promptFor(languageHint, strongerTeluguBias));
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
    language: json.language || languageCode(languageHint),
    words,
    source: "openai-whisper-1",
  };
}

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

  let result = await whisperOnce({
    audioBuffer,
    filename,
    apiKey,
    languageHint,
  });

  const isTelugu =
    languageHint === "te" ||
    languageHint === "te-IN" ||
    String(languageHint || "").startsWith("te");

  if (isTelugu && isKannadaHeavy(result.words)) {
    result = await whisperOnce({
      audioBuffer,
      filename,
      apiKey,
      languageHint,
      strongerTeluguBias: true,
    });
    result.retriedForKannada = true;
  }

  const te = result.words.filter((w) => scriptOf(w.text) === "te").length;
  const kn = result.words.filter((w) => scriptOf(w.text) === "kn").length;
  const la = result.words.filter((w) => scriptOf(w.text) === "la").length;
  result.scriptCounts = { te, kn, la };
  return result;
}

/** Express raw-body helper for multipart-ish simple uploads (base64 JSON). */
export function decodeBase64Audio(b64) {
  return Buffer.from(String(b64 || ""), "base64");
}
