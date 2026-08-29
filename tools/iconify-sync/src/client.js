/**
 * Minimal Iconify API client.
 * Docs: https://iconify.design/docs/api/
 */
const API = process.env.ICONIFY_API || "https://api.iconify.design";

export async function searchIcons(query, { limit = 24 } = {}) {
  const url = new URL(`${API}/search`);
  url.searchParams.set("query", query);
  url.searchParams.set("limit", String(limit));
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Iconify search failed (${res.status}): ${query}`);
  return res.json();
}

/**
 * Fetch SVG for prefix:name
 * @param {string} iconId e.g. "mdi:fire"
 */
export async function fetchSvg(iconId, { height = 256, color = "#FFEF5A" } = {}) {
  const [prefix, name] = String(iconId).split(":");
  if (!prefix || !name) throw new Error(`Invalid icon id: ${iconId}`);
  const url = new URL(`${API}/${prefix}/${name}.svg`);
  url.searchParams.set("height", String(height));
  if (color) url.searchParams.set("color", color.startsWith("#") ? color : `#${color}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Iconify SVG failed (${res.status}): ${iconId}`);
  return res.text();
}

export function iconIdToSlug(iconId) {
  return `iconify-${String(iconId).replace(":", "-").replace(/[^a-zA-Z0-9_-]/g, "-").toLowerCase()}`;
}

export function iconIdToName(iconId) {
  const [, name = iconId] = String(iconId).split(":");
  return name
    .split(/[-_]/)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(" ");
}
