#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${GLASSPATH_VERSION:-$(git describe --tags --abbrev=0 2>/dev/null || date +%Y.%m.%d)}"
ARCHES="${GLASSPATH_ARCHES:-amd64 arm64}"
OUT_DIR="${ROOT}/release"

mkdir -p "$OUT_DIR"

echo "Building frontend assets..."
(
  cd "${ROOT}/frontend"
  pnpm install --frozen-lockfile || pnpm install
  pnpm run build
)

for arch in $ARCHES; do
  echo "Building binary for linux/${arch}..."
  BUILD_ROOT="${OUT_DIR}/glasspath_${VERSION}_linux_${arch}"
  rm -rf "$BUILD_ROOT"
  mkdir -p "$BUILD_ROOT"

  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "${BUILD_ROOT}/glasspath" .

  cp README.md LICENSE "${BUILD_ROOT}" 2>/dev/null || true

  TARBALL="glasspath_${VERSION}_linux_${arch}.tar.gz"
  (
    cd "$OUT_DIR"
    tar -czf "$TARBALL" "glasspath_${VERSION}_linux_${arch}"
  )

  echo "Created ${OUT_DIR}/${TARBALL}"
done

echo "Done. Release artifacts in ${OUT_DIR}"
