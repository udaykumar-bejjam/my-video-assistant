#!/usr/bin/env node
/**
 * CaptionStudio ↔ Iconify sync CLI
 *
 * Usage:
 *   node src/cli.js search fire
 *   node src/cli.js add mdi:fire --tags power,hype,energy
 *   node src/cli.js sync-moods
 *   node src/cli.js sync-moods --moods power,cta --limit 1
 */
import path from "node:path";
import { fileURLToPath } from "node:url";
import { searchIcons } from "./client.js";
import { importIcon } from "./catalog.js";
import { MOOD_PRESETS, preferIcon, DEFAULT_COLOR } from "./presets.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, "../../..");

function parseArgs(argv) {
  const args = { _: [], flags: {} };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith("--")) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (!next || next.startsWith("--")) {
        args.flags[key] = true;
      } else {
        args.flags[key] = next;
        i += 1;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

function libraryPaths() {
  const primary = path.join(REPO_ROOT, "AssetLibraries", "pngs");
  const bundled = path.join(REPO_ROOT, "CaptionStudio", "Resources", "Libraries", "pngs");
  return {
    destDirs: [primary, bundled],
    catalogPath: path.join(primary, "catalog.json"),
  };
}

async function cmdSearch(query, limit = 12) {
  const data = await searchIcons(query, { limit: Number(limit) });
  const icons = data.icons || [];
  console.log(`Found ${data.total ?? icons.length} for "${query}" (showing ${icons.length}):\n`);
  for (const id of icons) {
    const preferred = preferIcon([id]) === id ? " ★" : "";
    console.log(`  ${id}${preferred}`);
  }
  console.log("\n★ = preferred collection (MIT/Apache-friendly sets)");
}

async function cmdAdd(iconId, flags) {
  const tags = String(flags.tags || "")
    .split(",")
    .map((t) => t.trim())
    .filter(Boolean);
  const size = Number(flags.size || 256);
  const color = flags.color || DEFAULT_COLOR;
  const { destDirs, catalogPath } = libraryPaths();
  const result = await importIcon({
    iconId,
    tags,
    size,
    color,
    destDirs,
    catalogPath,
    force: Boolean(flags.force),
  });
  console.log(JSON.stringify(result, null, 2));
}

async function cmdSyncMoods(flags) {
  const moodNames = flags.moods
    ? String(flags.moods).split(",").map((m) => m.trim()).filter(Boolean)
    : Object.keys(MOOD_PRESETS);
  const overrideLimit = flags.limit != null ? Number(flags.limit) : null;
  const size = Number(flags.size || 256);
  const color = flags.color || DEFAULT_COLOR;
  const { destDirs, catalogPath } = libraryPaths();

  const results = [];
  for (const mood of moodNames) {
    const preset = MOOD_PRESETS[mood];
    if (!preset) {
      console.warn(`Unknown mood: ${mood}`);
      continue;
    }
    const perQuery = overrideLimit ?? preset.limit;
    console.log(`\n== mood:${mood} (up to ${perQuery} per query) ==`);

    let addedForMood = 0;
    for (const query of preset.queries) {
      if (addedForMood >= (overrideLimit ?? preset.queries.length * preset.limit)) break;
      const data = await searchIcons(query, { limit: 24 });
      const pick = preferIcon(data.icons || []);
      if (!pick) {
        console.log(`  skip query="${query}" (no icons)`);
        continue;
      }
      try {
        const result = await importIcon({
          iconId: pick,
          tags: [...preset.tags, mood, query],
          size,
          color,
          destDirs,
          catalogPath,
          force: Boolean(flags.force),
        });
        console.log(`  ${result.status.padEnd(8)} ${pick} → ${result.slug || ""}`);
        results.push(result);
        if (result.status === "added" || result.status === "updated") addedForMood += 1;
      } catch (err) {
        console.error(`  FAIL ${pick}: ${err.message}`);
      }
      // Be polite to the public API
      await new Promise((r) => setTimeout(r, 120));
    }
  }

  const added = results.filter((r) => r.status === "added").length;
  const updated = results.filter((r) => r.status === "updated").length;
  const skipped = results.filter((r) => r.status === "skipped").length;
  console.log(`\nDone. added=${added} updated=${updated} skipped=${skipped}`);
  console.log(`Catalog: ${catalogPath}`);
}

function printHelp() {
  console.log(`CaptionStudio Iconify sync

Commands:
  search <query> [--limit 12]
  add <prefix:name> --tags a,b,c [--size 256] [--color #FFEF5A] [--force]
  sync-moods [--moods power,cta] [--limit 1] [--force]

Writes PNGs + catalog to:
  AssetLibraries/pngs/
  CaptionStudio/Resources/Libraries/pngs/
`);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const [cmd, ...rest] = args._;
  if (!cmd || cmd === "help" || args.flags.help) {
    printHelp();
    return;
  }
  if (cmd === "search") {
    await cmdSearch(rest[0] || "fire", args.flags.limit || 12);
    return;
  }
  if (cmd === "add") {
    if (!rest[0]) throw new Error("Usage: add <prefix:name> --tags …");
    await cmdAdd(rest[0], args.flags);
    return;
  }
  if (cmd === "sync-moods") {
    await cmdSyncMoods(args.flags);
    return;
  }
  throw new Error(`Unknown command: ${cmd}`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
