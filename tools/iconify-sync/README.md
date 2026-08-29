# Iconify → CaptionStudio PNG sync

Standalone tool that downloads icons from the [Iconify API](https://iconify.design/docs/api/), renders them to transparent PNGs, and registers them in the CaptionStudio `pngs` library so **AI Place / B-roll** can auto-pick them by tag.

## Setup

```bash
cd tools/iconify-sync
npm install
```

## Commands

```bash
# Search Iconify
npm start -- search fire
npm start -- search arrow --limit 20

# Import one icon with CaptionStudio mood tags
npm start -- add mdi:fire --tags power,hype,energy,hot

# Sync a curated set for all B-roll moods (power / reveal / emotion / numbers / cta)
npm start -- sync-moods

# Only CTA + power, one icon per search query
npm start -- sync-moods --moods power,cta --limit 1
```

## Where files go

| Path | Role |
|------|------|
| `AssetLibraries/pngs/*.png` + `catalog.json` | Source of truth |
| `CaptionStudio/Resources/Libraries/pngs/` | App bundle copy (kept in sync) |

## Options

| Flag | Default | Meaning |
|------|---------|---------|
| `--tags a,b` | — | Catalog tags (match B-roll moods) |
| `--size` | `256` | PNG edge length |
| `--color` | `#FFEF5A` | SVG fill (good on dark video) |
| `--force` | off | Overwrite existing catalog entry + file |
| `--moods` | all | `sync-moods` filter |
| `--limit` | preset | Max icons per mood query |

## License note

Iconify hosts many sets. This tool **prefers** MIT/Apache collections (`mdi`, `lucide`, `ri`, `boxicons`, …). Always check the collection license for your use case. Icons are cached locally — CaptionStudio does not call Iconify at edit time.
