#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${GLASSPATH_VERSION:-}"
AUTO_BUMP_PATCH="${AUTO_BUMP_PATCH:-0}"   # set to 1 to auto-increment patch if tag exists remotely
ARCHES="${GLASSPATH_ARCHES:-amd64 arm64}"
OUT_DIR="${ROOT}/release"
PUBLISH="${PUBLISH:-ask}"    # set to 1 to create/update GitHub release with assets; 'ask' prompts if TTY
PUSH_TAG="${PUSH_TAG:-0}"    # set to 1 to git push the release tag
GH_REPO="${GH_REPO:-}"
ALLOW_EXISTING_TAG="${ALLOW_EXISTING_TAG:-1}" # if tag exists remotely and PUSH_TAG=1, skip push and continue

if [[ -t 0 && "${CI:-}" != "true" ]]; then
  if [[ -z "$VERSION" ]]; then
    if git describe --tags --abbrev=0 >/dev/null 2>&1; then
      default_version="$(git describe --tags --abbrev=0)"
    else
      default_version="$(date +%Y.%m.%d)"
    fi
    read -rp "Release version [${default_version}]: " input_version
    VERSION="${input_version:-$default_version}"
  fi

  read -rp "Publish to GitHub after build? [y/N]: " ans_pub
  if [[ "$ans_pub" =~ ^[Yy] ]]; then PUBLISH=1; else PUBLISH=0; fi

  read -rp "Push tag to origin? [y/N]: " ans_tag
  if [[ "$ans_tag" =~ ^[Yy] ]]; then PUSH_TAG=1; else PUSH_TAG=0; fi

  read -rp "Auto-bump patch if tag exists? [y/N]: " ans_bump
  if [[ "$ans_bump" =~ ^[Yy] ]]; then AUTO_BUMP_PATCH=1; else AUTO_BUMP_PATCH=0; fi
fi

# Colors for nicer output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m"

log()  { printf "%b[release]%b %s\n" "$YELLOW" "$NC" "$*" >&2; }
good() { printf "%b[release]%b %s\n" "$GREEN" "$NC" "$*" >&2; }
bad()  { printf "%b[release]%b %s\n" "$RED" "$NC" "$*" >&2; }

pick_version() {
  local base_ver="$1"
  local ver="$base_ver"

  if [[ -z "$ver" ]]; then
    if git describe --tags --abbrev=0 >/dev/null 2>&1; then
      ver="$(git describe --tags --abbrev=0)"
      log "Using latest tag: ${ver}"
    else
      ver="$(date +%Y.%m.%d)"
      log "No tags found; using date-based version: ${ver}"
    fi
  fi

  if [[ "$AUTO_BUMP_PATCH" != "1" ]]; then
    echo "$ver"
    return
  fi

  # Auto-increment patch if tag exists on remote origin.
  while git ls-remote --tags origin "refs/tags/${ver}" >/dev/null 2>&1; do
    if [[ "$ver" =~ ^v?([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      local major="${BASH_REMATCH[1]}"
      local minor="${BASH_REMATCH[2]}"
      local patch="${BASH_REMATCH[3]}"
      patch=$((patch + 1))
      ver="v${major}.${minor}.${patch}"
      log "Tag exists remotely; auto-bumped to ${ver}"
    else
      bad "Cannot auto-bump version '${ver}' (not semantic)."
      break
    fi
  done

  echo "$ver"
}

VERSION="$(pick_version "$VERSION")"

log "Version: ${VERSION}"
log "Arches: ${ARCHES}"
log "Publish to GitHub: ${PUBLISH}"
log "Push tag: ${PUSH_TAG}"

TAR_VERSION="${VERSION#v}"

# If still "ask" (non-interactive), default to 0.
if [[ "$PUBLISH" == "ask" ]]; then
  PUBLISH=0
fi

mkdir -p "$OUT_DIR"

log "Building frontend assets..."
(
  cd "${ROOT}/frontend"
  pnpm install --frozen-lockfile || pnpm install
  pnpm run build
)

for arch in $ARCHES; do
  log "Building binary for linux/${arch}..."
  BUILD_ROOT="${OUT_DIR}/glasspath_${TAR_VERSION}_linux_${arch}"
  rm -rf "$BUILD_ROOT"
  mkdir -p "$BUILD_ROOT"

  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -o "${BUILD_ROOT}/glasspath" .

  cp README.md LICENSE "${BUILD_ROOT}" 2>/dev/null || true

  TARBALL="glasspath_${TAR_VERSION}_linux_${arch}.tar.gz"
  (
    cd "$OUT_DIR"
    tar -czf "$TARBALL" "glasspath_${TAR_VERSION}_linux_${arch}"
  )

  good "Created ${OUT_DIR}/${TARBALL}"
done

good "Done. Release artifacts in ${OUT_DIR}"

if [[ "$PUBLISH" != "1" ]]; then
  log "PUBLISH=1 not set; skipping GitHub release upload."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  bad "PUBLISH=1 but GitHub CLI 'gh' not found. Install gh or set PUBLISH=0."
  exit 1
fi

# Verify auth
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  bad "GitHub CLI is not authenticated. Please run 'gh auth login' (GitHub.com, HTTPS) or set GH_TOKEN, then re-run this script."
  exit 1
fi

# Determine GH_REPO if not provided (expects remote origin to be ssh/https URL).
if [[ -z "$GH_REPO" ]]; then
  origin_url="$(git config --get remote.origin.url || true)"
  if [[ -z "$origin_url" ]]; then
    bad "Unable to determine remote.origin.url; set GH_REPO=owner/repo."
    exit 1
  fi
  # Handle ssh URL: git@github.com:owner/repo.git
  if [[ "$origin_url" =~ ^git@[^:]+:([^/]+/[^/]+)(\.git)?$ ]]; then
    GH_REPO="${BASH_REMATCH[1]}"
  # Handle https URL: https://github.com/owner/repo(.git)
  elif [[ "$origin_url" =~ ^https://github.com/([^/]+/[^/]+)(\.git)?$ ]]; then
    GH_REPO="${BASH_REMATCH[1]}"
  else
    # Fallback: strip protocol/ending heuristically
    GH_REPO="${origin_url##*:}"
    GH_REPO="${GH_REPO##*/}"
  fi
  GH_REPO="${GH_REPO%.git}"
fi

log "Using GH_REPO=$GH_REPO"

# Ensure tag exists locally; create annotated tag if missing.
if git rev-parse "refs/tags/${VERSION}" >/dev/null 2>&1; then
  log "Tag ${VERSION} already exists locally."
else
  git tag -a "$VERSION" -m "Release $VERSION"
  good "Created tag ${VERSION}."
fi

# Optionally push tag.
if [[ "$PUSH_TAG" == "1" ]]; then
  log "Pushing tag ${VERSION} to origin..."
  if ! git push origin "$VERSION"; then
    if [[ "$ALLOW_EXISTING_TAG" == "1" ]]; then
      log "Tag ${VERSION} already exists remotely; skipping push and continuing."
    else
      bad "Failed to push tag ${VERSION} to origin."
      exit 1
    fi
  fi
fi

ASSETS=()
for arch in $ARCHES; do
  ASSETS+=("${OUT_DIR}/glasspath_${TAR_VERSION}_linux_${arch}.tar.gz")
done

# Create or update GitHub release and upload assets.
if gh release view "$VERSION" --repo "$GH_REPO" >/dev/null 2>&1; then
  log "Release ${VERSION} exists; uploading assets (will clobber)."
  if ! gh release upload "$VERSION" "${ASSETS[@]}" --clobber --repo "$GH_REPO"; then
    bad "Failed to upload assets to existing release ${VERSION}."
    exit 1
  fi
else
  log "Creating release ${VERSION} on GitHub..."
  if ! gh release create "$VERSION" "${ASSETS[@]}" \
    --title "$VERSION" \
    --notes "Release $VERSION" \
    --repo "$GH_REPO"; then
    bad "Failed to create release ${VERSION}."
    exit 1
  fi
fi

good "Publish complete."
