#!/usr/bin/env bash
set -euo pipefail

REPO="allisonhere/Glasspath"
VERSION="${GLASSPATH_VERSION:-latest}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(curl -fsSL https://api.github.com/repos/${REPO}/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' || true)"
  if [[ -z "$VERSION" ]]; then
    echo "No releases found for ${REPO}; publish a tarball or set GLASSPATH_VERSION." >&2
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
ACTION="${ACTION:-install}"

if [[ "$ACTION" == "uninstall" ]]; then
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  rm -f "$BIN_LINK"
  rm -rf "$INSTALL_DIR"
  echo "Glasspath uninstalled."
  exit 0
fi

echo "Downloading ${URL} ..."
if ! curl -fL "$URL" -o "/tmp/${TARBALL}"; then
  echo "Failed to download ${URL}. Ensure release asset exists." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
tar -C "$INSTALL_DIR" -xzf "/tmp/${TARBALL}"
ln -sf "$INSTALL_DIR/glasspath" "$BIN_LINK"

cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
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

systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo "Glasspath running on http://${ADDR}:${PORT}"
