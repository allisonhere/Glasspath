#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${GLASSPATH_VERSION:-}"
if [[ -z "$VERSION" ]]; then
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git describe --tags --abbrev=0)"
    echo "Using latest tag: ${VERSION}"
  else
    VERSION="$(date +%Y.%m.%d)"
    echo "No tags found; using date-based version: ${VERSION}"
  fi
fi

ARCHES="${GLASSPATH_ARCHES:-amd64 arm64}"
OUT_DIR="${ROOT}/release"
PUBLISH="${PUBLISH:-0}"      # set to 1 to create/update GitHub release with assets
PUSH_TAG="${PUSH_TAG:-0}"    # set to 1 to git push the release tag
GH_REPO="${GH_REPO:-}"

echo "Version: ${VERSION}"
echo "Arches: ${ARCHES}"
echo "Publish to GitHub: ${PUBLISH}"
echo "Push tag: ${PUSH_TAG}"

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

if [[ "$PUBLISH" != "1" ]]; then
  echo "PUBLISH=1 not set; skipping GitHub release upload."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "PUBLISH=1 but GitHub CLI 'gh' not found. Install gh or set PUBLISH=0."
  exit 1
fi

# Determine GH_REPO if not provided (expects remote origin to be ssh/https URL).
if [[ -z "$GH_REPO" ]]; then
  origin_url="$(git config --get remote.origin.url || true)"
  if [[ -z "$origin_url" ]]; then
    echo "Unable to determine remote.origin.url; set GH_REPO=owner/repo."
    exit 1
  fi
  GH_REPO="${origin_url##*:}"
  GH_REPO="${GH_REPO##*/}"
  # handle https://github.com/owner/repo(.git)
  if [[ "$origin_url" == https://github.com/* ]]; then
    GH_REPO="${origin_url#https://github.com/}"
  fi
  GH_REPO="${GH_REPO%.git}"
fi

echo "Using GH_REPO=$GH_REPO"

# Ensure tag exists locally; create annotated tag if missing.
if git rev-parse "refs/tags/${VERSION}" >/dev/null 2>&1; then
  echo "Tag ${VERSION} already exists locally."
else
  git tag -a "$VERSION" -m "Release $VERSION"
  echo "Created tag ${VERSION}."
fi

# Optionally push tag.
if [[ "$PUSH_TAG" == "1" ]]; then
  echo "Pushing tag ${VERSION} to origin..."
  git push origin "$VERSION"
fi

ASSETS=()
for arch in $ARCHES; do
  ASSETS+=("${OUT_DIR}/glasspath_${VERSION}_linux_${arch}.tar.gz")
done

# Create or update GitHub release and upload assets.
if gh release view "$VERSION" --repo "$GH_REPO" >/dev/null 2>&1; then
  echo "Release ${VERSION} exists; uploading assets (may overwrite)."
  gh release upload "$VERSION" "${ASSETS[@]}" --clobber --repo "$GH_REPO"
else
  echo "Creating release ${VERSION} on GitHub..."
  gh release create "$VERSION" "${ASSETS[@]}" \
    --title "$VERSION" \
    --notes "Release $VERSION" \
    --repo "$GH_REPO"
fi

echo "Publish complete."
