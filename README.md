# Glasspath

Glasspath is a themed and slightly modernized fork of [File Browser](https://github.com/filebrowser/filebrowser) that keeps the familiar single-binary file manager while layering updated styling (Obsidian-inspired darks, neon accents, refreshed info panels, and Vue/Naive UI components).

> **Credit:** The core application, server, and original frontend are by the File Browser contributors under the Apache 2.0 license. This fork builds on their work—see [LICENSE](LICENSE) for details.

## Quick start

Backend:
- Go 1.25+: `go run .` (serves API on `:8080` by default)

Frontend:
- From `frontend/`: `pnpm install` (set `PNPM_IGNORE_NODEENGINE_CHECK=1` if you stay on Node 20), then `pnpm dev`
- Visit `http://localhost:5173` (proxies API to `:8080`)

Production build:
- `pnpm run build` in `frontend/` to emit assets into `frontend/dist/`
- Build the Go binary: `go build -o filebrowser`

## Notes

- Themes: choose Light, Dawn, Dark, or Noir in Settings → Branding. Noir uses neutral charcoal backgrounds with purple accents.
- The “Info” panel shows size, modified time, resolution (for images), permissions (symbolic + octal), and checksums on demand.

## Contributing

This fork lives at `git@github.com:allisonhere/Glasspath.git`. PRs are welcome; please keep server compatibility with upstream and note any UI changes in your PR description.
