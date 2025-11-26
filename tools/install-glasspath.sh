#!/usr/bin/env bash
set -euo pipefail

REPO="allisonhere/Glasspath"
VERSION="${GLASSPATH_VERSION:-latest}"
ARCH="$(uname -m)"

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
    echo "Could not resolve latest version from GitHub releases." >&2
    exit 1
  fi
fi

TARBALL="glasspath_${VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${TARBALL}"

INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE_NAME="glasspath"
PORT="${PORT:-8080}"
ADDR="${ADDR:-0.0.0.0}"

echo "Downloading ${URL} ..."
curl -fL "$URL" -o "/tmp/${TARBALL}"

sudo mkdir -p "$INSTALL_DIR"
sudo tar -C "$INSTALL_DIR" -xzf "/tmp/${TARBALL}"
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
