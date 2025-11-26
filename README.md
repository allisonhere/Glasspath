# Glasspath

Glasspath is a themed and modernized fork of [File Browser](https://github.com/filebrowser/filebrowser) that keeps the familiar single-binary file manager while layering updated styling (Obsidian/Glassmorphism/Pro themes), refreshed info panels, command palette + keyboard shortcuts, and Vue/Naive UI components.

> **Credit:** The core application, server, and original frontend are by the File Browser contributors under the Apache 2.0 license. This fork builds on their work—see [LICENSE](LICENSE) for details.

## Quick start

Backend:
- Go 1.25+: `go run .` (serves API on `:8080` by default)

Frontend:
- From `frontend/`: `pnpm install` (set `PNPM_IGNORE_NODEENGINE_CHECK=1` if you stay on Node 20), then `pnpm dev` (add `--host 0.0.0.0 --port 5173` for LAN)
- Visit `http://localhost:5173` (proxies API to `:8080`)

Production build:
- `pnpm run build` in `frontend/` to emit assets into `frontend/dist/`
- Build the Go binary: `go build -o filebrowser`

## One-line install (LXC/VM)

Assuming you publish release tarballs (see `tools/build-release.sh`), install/start via systemd:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/allisonhere/Glasspath/master/tools/install-glasspath.sh)"
```

Options: `PORT=8080 ADDR=0.0.0.0 GLASSPATH_VERSION=v1.0.0` before the command to override defaults. Artifacts should be named `glasspath_<version>_linux_<arch>.tar.gz` (amd64/arm64).

## Notes

- Themes: Light, Dawn, Dark, Noir, Glassmorphism, Pro (dense). Use Settings → Branding or the command palette (Ctrl/Cmd+K) to switch.
- UI: command palette, keyboard navigation (arrows/Enter, search/download/rename/delete shortcuts), badges for shared/permissions, sticky headers, and richer previews with metadata sidebar/zoom.
- Info panel: size, modified time, resolution (images), permissions (symbolic + octal), and checksums on demand.

## Contributing

This fork lives at `git@github.com:allisonhere/Glasspath.git`. PRs are welcome; please keep server compatibility with upstream and note any UI changes in your PR description.
