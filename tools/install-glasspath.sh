#!/usr/bin/env bash
set -euo pipefail

REPO="allisonhere/Glasspath"
VERSION="${GLASSPATH_VERSION:-latest}"
ARCH="$(uname -m)"
ACTION="${ACTION:-install}"

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep -oP '"tag_name":\s*"\K[^"]+' || true)"
  if [[ -z "$VERSION" ]]; then
    echo "No releases found; falling back to source build (branch main)." >&2
    VERSION="main"
  fi
fi

TARBALL="glasspath_${VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"

INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE_NAME="glasspath"
PORT="${PORT:-8080}"
ADDR="${ADDR:-0.0.0.0}"

if [[ "$ACTION" == "uninstall" ]]; then
  echo "Stopping ${SERVICE_NAME}..."
  sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  sudo systemctl daemon-reload
  sudo rm -f "$BIN_LINK"
  sudo rm -rf "$INSTALL_DIR"
  echo "Glasspath uninstalled."
  exit 0
fi

install_from_release() {
  echo "Attempting to download ${URL} ..."
  if ! curl -fL "$URL" -o "/tmp/${TARBALL}"; then
    return 1
  fi
  sudo mkdir -p "$INSTALL_DIR"
  sudo tar -C "$INSTALL_DIR" -xzf "/tmp/${TARBALL}"
}

install_from_source() {
  echo "Release not found; building from source (requires git, go>=1.25, node>=20, pnpm)..."
  command -v git >/dev/null || { echo "git not found"; exit 1; }
  command -v go >/dev/null || { echo "go not found"; exit 1; }
  command -v pnpm >/dev/null || { echo "pnpm not found"; exit 1; }

  SRC_DIR="$(mktemp -d)"
  git clone --depth 1 --branch "${VERSION#v}" "https://github.com/${REPO}.git" "$SRC_DIR" 2>/dev/null || \
    git clone --depth 1 "https://github.com/${REPO}.git" "$SRC_DIR"

  (cd "$SRC_DIR/frontend" && pnpm install && pnpm run build)
  (cd "$SRC_DIR" && CGO_ENABLED=0 go build -o "${SRC_DIR}/glasspath" .)

  sudo mkdir -p "$INSTALL_DIR"
  sudo cp "${SRC_DIR}/glasspath" "$INSTALL_DIR/"
}

if ! install_from_release; then
  install_from_source
fi

sudo ln -sf "$INSTALL_DIR/glasspath" "$BIN_LINK"

sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" >/dev/null <<EOF
[Unit]
Description=Glasspath file manager
After=network.target

[Service]
Type=simple
ExecStart=${BIN_LINK} --address ${ADDR} --port ${PORT}
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
Environment=HOME=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now "${SERVICE_NAME}"

echo "Glasspath installed."
echo "Service: systemctl status ${SERVICE_NAME}"
echo "URL: http://${ADDR}:${PORT}"
