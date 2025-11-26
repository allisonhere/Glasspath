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
  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/${REPO}/releases/latest || true)"
else
  RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/${REPO}/releases/tags/${VERSION} || true)"
  if [[ -z "$RELEASE_JSON" && "$VERSION" == v* ]]; then
    RELEASE_JSON="$(curl -fsSL https://api.github.com/repos/${REPO}/releases/tags/${VERSION#v}" || true)"
  fi
fi

if [[ -z "$RELEASE_JSON" ]]; then
  echo "No releases found for ${REPO}; publish a tarball or set GLASSPATH_VERSION." >&2
  exit 1
fi

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(echo "$RELEASE_JSON" | grep -oP '"tag_name":\s*"\K[^"]+' | head -n1)"
fi

ASSET_URL=$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | \
  grep -Ei "$( [[ "$ARCH" == "amd64" ]] && echo '(linux.*amd64|amd64.*linux|linux.*x86_64|x86_64.*linux)' || echo '(linux.*arm64|arm64.*linux|linux.*aarch64|aarch64.*linux)' )" | head -n1)
if [[ -z "$ASSET_URL" ]]; then
  ASSET_URL=$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | head -n1)
fi
if [[ -z "$ASSET_URL" ]]; then
  echo "No suitable release asset found for arch ${ARCH}." >&2
  exit 1
fi

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
if ! curl -fL "$ASSET_URL" -o "/tmp/glasspath.tar.gz"; then
  echo "Failed to download ${ASSET_URL}. Ensure release asset exists." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
tar -C "$INSTALL_DIR" -xzf "/tmp/glasspath.tar.gz"
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
