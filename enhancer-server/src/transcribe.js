/**
 * OpenAI transcription for CaptionStudio.
 *
 * whisper-1 does NOT support language=te (Telugu) — it 400s.
 * Kannada (kn) IS supported, which caused Telugu→Kannada mix-ups.
 * Telugu uses gpt-transcribe with languages[]=te,en instead.
 */
import { Buffer } from "node:buffer";

function teluguPrompt(strong = false) {
  if (strong) {
    return (
      "నమస్కారం ఇది తెలుగు వీడియో. Write ONLY Telugu script (తెలుగు) for Telugu words — NEVER Kannada (ಕನ್ನಡ). " +
      "English words in Latin: subscribe, follow, wow, video, Instagram."
    );
  }
  return (
    "నమస్కారం — తెలుగు మరియు English mixed (Tanglish). " +
    "Telugu words in Telugu script (తెలుగు), not Kannada. English loanwords in Latin letters."
  );
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
  if (indic < 2) return kn > 0 && te === 0;
  return kn > te;
}

function stampWords(text, duration = 10) {
  const parts = String(text || "")
    .split(/\s+/)
    .map((p) => p.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ""))
    .filter(Boolean);
  if (!parts.length) return [];
  const videoDur = Math.max(1, Number(duration) || 10);
  const weights = parts.map((p) => {
    let boost = 1;
    for (const ch of p) {
      const c = ch.codePointAt(0);
      if (c >= 0x0c00 && c <= 0x0c7f) boost = 1.45;
      else if (c >= 0x0900 && c <= 0x097f) boost = Math.max(boost, 1.3);
    }
    return Math.max(boost > 1 ? 1.2 : 1, p.length * boost);
  });
  const total = weights.reduce((a, b) => a + b, 0) || 1;
  // Natural speaking window — do not stretch a short transcript across the full video.
  const natural = total / 11;
  const leadIn = Math.min(0.2, videoDur * 0.01);
  const usable = Math.min(videoDur - leadIn, Math.max(natural, parts.length * 0.28));
  let t = leadIn;
  const stamps = parts.map((part, i) => {
    const span = usable * (weights[i] / total);
    const indic = [...part].some((ch) => {
      const c = ch.codePointAt(0);
      return (c >= 0x0c00 && c <= 0x0c7f) || (c >= 0x0900 && c <= 0x097f);
    });
    const dwell = Math.max(indic ? 0.3 : 0.22, span);
    const end = i === parts.length - 1 ? Math.min(videoDur, leadIn + usable) : Math.min(videoDur, t + dwell);
    const start = t;
    t = Math.max(start + 0.12, end);
    return { text: part, startTime: start, endTime: t };
  });
  const last = stamps[stamps.length - 1];
  // Compress only if overrun — never expand to fill the tail.
  if (last && last.endTime > videoDur + 0.05) {
    const srcStart = stamps[0].startTime;
    const srcEnd = last.endTime;
    const srcSpan = Math.max(0.1, srcEnd - srcStart);
    const dstSpan = Math.max(0.5, videoDur - srcStart);
    return stamps.map((w) => {
      const a = (w.startTime - srcStart) / srcSpan;
      const b = (w.endTime - srcStart) / srcSpan;
      return {
        text: w.text,
        startTime: srcStart + a * dstSpan,
        endTime: srcStart + Math.max(a + 0.06, b) * dstSpan,
      };
    });
  }
  return stamps;
}

async function gptTranscribe({ audioBuffer, filename, apiKey, languages, prompt }) {
  const form = new FormData();
  form.append("model", "gpt-transcribe");
  form.append("response_format", "json");
  form.append("temperature", "0");
  form.append("prompt", prompt);
  for (const lang of languages) {
    form.append("languages[]", lang);
  }
  form.append("file", new Blob([audioBuffer], { type: "audio/m4a" }), filename);

  const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`Transcription API ${res.status}: ${text.slice(0, 400)}`);
    err.status = res.status;
    err.body = text;
    throw err;
  }
  const json = JSON.parse(text);
  return String(json.text || "").trim();
}

async function whisper1PromptOnly({ audioBuffer, filename, apiKey, prompt }) {
  const form = new FormData();
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");
  form.append("timestamp_granularities[]", "word");
  form.append("temperature", "0");
  form.append("prompt", prompt);
  // Never send language=te — OpenAI returns 400 unsupported_language.
  form.append("file", new Blob([audioBuffer], { type: "audio/m4a" }), filename);

  const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}` },
    body: form,
  });
  const text = await res.text();
  if (!res.ok) {
    const err = new Error(`Whisper API ${res.status}: ${text.slice(0, 400)}`);
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
  return {
    text: json.text || words.map((w) => w.text).join(" "),
    language: json.language || null,
    words,
  };
}

export async function transcribeWithWhisper({
  audioBuffer,
  filename = "audio.m4a",
  languageHint = "te",
  apiKey = process.env.OPENAI_API_KEY,
  duration = 10,
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

  const isTelugu =
    languageHint === "te" ||
    languageHint === "te-IN" ||
    String(languageHint || "").startsWith("te");

  if (!isTelugu) {
    // Non-Telugu: whisper-1 with supported language codes.
    const form = new FormData();
    form.append("model", "whisper-1");
    form.append("response_format", "verbose_json");
    form.append("timestamp_granularities[]", "word");
    form.append("temperature", "0");
    if (languageHint === "hi" || languageHint === "hi-IN") form.append("language", "hi");
    if (languageHint === "en" || languageHint === "en-US") form.append("language", "en");
    form.append("file", new Blob([audioBuffer], { type: "audio/m4a" }), filename);
    const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    });
    const text = await res.text();
    if (!res.ok) {
      const err = new Error(`Whisper API ${res.status}: ${text.slice(0, 400)}`);
      err.status = res.status;
      throw err;
    }
    const json = JSON.parse(text);
    const words = (json.words || []).map((w) => ({
      text: String(w.word || "").trim(),
      startTime: Number(w.start) || 0,
      endTime: Math.max(Number(w.end) || 0, (Number(w.start) || 0) + 0.05),
    })).filter((w) => w.text);
    return { text: json.text, language: json.language, words, source: "openai-whisper-1" };
  }

  // Telugu path — gpt-transcribe with te+en (whisper-1 rejects language=te).
  let transcriptText;
  let source = "openai-gpt-transcribe";
  try {
    transcriptText = await gptTranscribe({
      audioBuffer,
      filename,
      apiKey,
      languages: ["te", "en"],
      prompt: teluguPrompt(false),
    });
    let words = stampWords(transcriptText, duration);
    if (isKannadaHeavy(words)) {
      transcriptText = await gptTranscribe({
        audioBuffer,
        filename,
        apiKey,
        languages: ["te", "en"],
        prompt: teluguPrompt(true),
      });
      words = stampWords(transcriptText, duration);
    }
    const te = words.filter((w) => scriptOf(w.text) === "te").length;
    const kn = words.filter((w) => scriptOf(w.text) === "kn").length;
    const la = words.filter((w) => scriptOf(w.text) === "la").length;
    return {
      text: transcriptText,
      language: "te+en",
      words,
      scriptCounts: { te, kn, la },
      source,
    };
  } catch (err) {
    const body = String(err.body || err.message || "");
    if (err.status === 400 && /language|unsupported/i.test(body)) {
      source = "openai-whisper-1-prompt";
      const fallback = await whisper1PromptOnly({
        audioBuffer,
        filename,
        apiKey,
        prompt: teluguPrompt(true),
      });
      let words = fallback.words?.length
        ? fallback.words
        : stampWords(fallback.text, duration);
      return {
        text: fallback.text,
        language: fallback.language,
        words,
        source,
        note: "whisper-1 fallback (no language=te)",
      };
    }
    throw err;
  }
}

export function decodeBase64Audio(b64) {
  return Buffer.from(String(b64 || ""), "base64");
}
