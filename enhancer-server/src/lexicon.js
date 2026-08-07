/**
 * Per-language strong-word lexicons for B-roll / sticker triggers.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LEXICON_ROOT = path.resolve(__dirname, "../../AssetLibraries/lexicons");

const cache = new Map();

function langKey(language = "en-US") {
  const lower = String(language || "en").toLowerCase();
  if (lower.startsWith("hi")) return "hi";
  if (lower.startsWith("te")) return "te";
  return "en";
}

export function loadLexicon(language = "en-US") {
  const key = langKey(language);
  if (cache.has(key)) return cache.get(key);
  const file = path.join(LEXICON_ROOT, `${key}.json`);
  let data = { language: key, categories: {} };
  if (fs.existsSync(file)) {
    data = JSON.parse(fs.readFileSync(file, "utf8"));
  }
  // Flatten lookup: word → category
  const byWord = new Map();
  for (const [category, words] of Object.entries(data.categories || {})) {
    for (const w of words || []) {
      byWord.set(String(w).toLowerCase(), category);
    }
  }
  const packed = { ...data, byWord };
  cache.set(key, packed);
  return packed;
}

export function clearLexiconCache() {
  cache.clear();
}

/** Strip light punctuation for matching. */
export function normalizeToken(text) {
  return String(text || "")
    .trim()
    .replace(/^[\s"'“”‘’(]+|[)"'“”‘’.,!?…:;]+$/g, "")
    .toLowerCase();
}

/**
 * Classify a token into power | reveal | emotion | numbers | cta | null.
 * Numbers (digits / %) always count as "numbers".
 */
export function classifyStrongWord(text, language = "en-US") {
  const token = normalizeToken(text);
  if (!token) return null;
  if (/^\d+(\.\d+)?%?$/.test(token) || /^\d+k$/i.test(token)) return "numbers";
  const lex = loadLexicon(language);
  if (lex.byWord.has(token)) return lex.byWord.get(token);
  // Soft English stems
  if (language.toLowerCase().startsWith("en") || langKey(language) === "en") {
    if (/^(fire|crazy|insane|epic|hype)/.test(token)) return "power";
    if (/^(secret|reveal|watch|wait)/.test(token)) return "reveal";
    if (/^(love|heart|wow|amaz)/.test(token)) return "emotion";
    if (/^(follow|share|subscribe|like|click|go)$/.test(token)) return "cta";
  }
  return null;
}

export function isStrongWord(text, language = "en-US") {
  return classifyStrongWord(text, language) != null;
}

/** Prefer lexicon matches, then longer tokens. Boost native script for TE/HI. */
export function scoreWordSignificance(text, language = "en-US") {
  const token = normalizeToken(text);
  if (!token || token.length < 2) return -1;
  const cat = classifyStrongWord(token, language);
  let score = token.length;
  if (cat === "power" || cat === "cta") score += 40;
  else if (cat === "reveal" || cat === "emotion") score += 35;
  else if (cat === "numbers") score += 30;
  // Code-switched videos: also credit English lexicon hits.
  const lang = String(language || "");
  if (!lang.startsWith("en")) {
    const enCat = classifyStrongWord(token, "en-US");
    if (enCat === "power" || enCat === "cta") score = Math.max(score, token.length + 40);
    else if (enCat === "reveal" || enCat === "emotion") score = Math.max(score, token.length + 35);
  }
  // Prefer Telugu / Devanagari tokens so English inserts don't monopolize hits.
  if (/[\u0C00-\u0C7F]/.test(token) && lang.startsWith("te")) score += 28;
  if (/[\u0900-\u097F]/.test(token) && lang.startsWith("hi")) score += 28;
  return score;
}

/** Mood tags for GIF/PNG selection from a strong-word category. */
export function tagsForCategory(category) {
  switch (category) {
    case "power":
      return ["power", "impact", "hype", "energy", "hot", "celebration", "win", "boom", "fire", "slam"];
    case "reveal":
      return ["reveal", "focus", "highlight", "new", "premium", "sparkle", "wow", "shine"];
    case "emotion":
      return ["love", "emotion", "emotional", "celebration", "cheer", "like", "heart", "pulse"];
    case "numbers":
      return ["point", "highlight", "focus", "ui", "label"];
    case "cta":
      return ["cta", "direction", "point", "product", "premium", "arrow"];
    default:
      return ["hype", "impact", "focus"];
  }
}
