import fs from "node:fs";
import path from "node:path";
import { Resvg } from "@resvg/resvg-js";
import { fetchSvg, iconIdToName, iconIdToSlug } from "./client.js";
import { DEFAULT_COLOR } from "./presets.js";

export function loadCatalog(catalogPath) {
  if (!fs.existsSync(catalogPath)) {
    return { version: 1, library: "pngs", items: [] };
  }
  return JSON.parse(fs.readFileSync(catalogPath, "utf8"));
}

export function saveCatalog(catalogPath, catalog) {
  fs.mkdirSync(path.dirname(catalogPath), { recursive: true });
  fs.writeFileSync(catalogPath, `${JSON.stringify(catalog, null, 2)}\n`, "utf8");
}

export function svgToPng(svg, size = 256) {
  const resvg = new Resvg(svg, {
    fitTo: { mode: "width", value: size },
    background: "rgba(0,0,0,0)",
  });
  const png = resvg.render();
  return png.asPng();
}

/**
 * Download one Iconify icon into png folders + catalog.
 */
export async function importIcon({
  iconId,
  tags = [],
  size = 256,
  color = DEFAULT_COLOR,
  destDirs = [],
  catalogPath,
  force = false,
}) {
  const slug = iconIdToSlug(iconId);
  const fileName = `${slug}.png`;
  const catalog = loadCatalog(catalogPath);
  const existing = catalog.items.find((i) => i.id === slug || i.iconifyId === iconId);

  if (existing && !force) {
    return { status: "skipped", iconId, slug, reason: "already in catalog" };
  }

  const svg = await fetchSvg(iconId, { height: size, color });
  const png = svgToPng(svg, size);

  for (const dir of destDirs) {
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, fileName), png);
  }

  const entry = {
    id: slug,
    name: iconIdToName(iconId),
    tags: Array.from(new Set(tags)),
    file: fileName,
    defaultDuration: 1.8,
    defaultScale: 1.0,
    width: size,
    height: size,
    source: "iconify",
    iconifyId: iconId,
    licenseNote: "Check Iconify collection license (prefer MIT/Apache)",
  };

  if (existing) {
    Object.assign(existing, entry);
  } else {
    catalog.items.push(entry);
  }
  saveCatalog(catalogPath, catalog);

  // Mirror catalog into sibling destDirs that look like pngs folders
  for (const dir of destDirs) {
    const mirrorCatalog = path.join(dir, "catalog.json");
    if (path.resolve(mirrorCatalog) === path.resolve(catalogPath)) continue;
    saveCatalog(mirrorCatalog, catalog);
  }

  return { status: existing ? "updated" : "added", iconId, slug, fileName };
}
