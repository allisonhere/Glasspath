#!/usr/bin/env bash
set -euo pipefail

# Config
REPO="allisonhere/Glasspath"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac

PORT="${PORT:-8080}"
ADDR="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -z "$ADDR" ] && ADDR="$(hostname -I | awk '{print $1}')"
[ -z "$ADDR" ] && ADDR="0.0.0.0"
ADMIN_USER="admin"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-SetMe123}"
INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE="/etc/systemd/system/glasspath.service"
ASSET_URL="${GLASSPATH_URL:-}"

# Resolve asset URL
if [[ -z "$ASSET_URL" ]]; then
  RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" || true)"
  ASSET_URL="$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -m1 -E 'linux_'"$ARCH"'.*tar\.gz$' || true)"
  if [[ -z "$ASSET_URL" ]]; then
    ASSET_URL="$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -m1 -E 'tar\.gz$' || true)"
  fi
fi

if [[ -z "$ASSET_URL" ]]; then
  echo "No release tarball found. Set GLASSPATH_URL to the asset URL." >&2
  exit 1
fi

# Stop and clean
systemctl stop glasspath 2>/dev/null || true
rm -rf "$INSTALL_DIR" /tmp/gp.tar.gz "$SERVICE"

# Download and extract
mkdir -p "$INSTALL_DIR"
curl -fL "$ASSET_URL" -o /tmp/gp.tar.gz
tar -C "$INSTALL_DIR" --strip-components=1 -xzf /tmp/gp.tar.gz || true

# Find binary
BIN="$(find "$INSTALL_DIR" -type f \( -name glasspath -o -perm -111 \) | head -n1)"
if [[ -z "$BIN" ]]; then
  echo "No glasspath binary found in archive. Contents:" >&2
  find "$INSTALL_DIR" -maxdepth 3 -type f >&2 || true
  exit 1
fi
chmod +x "$BIN"
ln -sf "$BIN" "$BIN_LINK"

# Reset DB and set admin
rm -f "$INSTALL_DIR/filebrowser.db"
"$BIN" --database "$INSTALL_DIR/filebrowser.db" users add "$ADMIN_USER" --password "$ADMIN_PASSWORD" --perm.admin --scope "/" >/dev/null 2>&1 || \
"$BIN" --database "$INSTALL_DIR/filebrowser.db" users update "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null 2>&1 || true
echo -e "${ADMIN_USER}\n${ADMIN_PASSWORD}" > "${INSTALL_DIR}/admin_credentials.txt"

# Service
cat >"$SERVICE" <<EOF
[Unit]
Description=Glasspath
After=network.target
[Service]
Type=simple
ExecStart=${BIN_LINK} --address ${ADDR} --port ${PORT} --database ${INSTALL_DIR}/filebrowser.db
WorkingDirectory=${INSTALL_DIR}
Restart=on-failure
Environment=HOME=${INSTALL_DIR}
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now glasspath || true

echo "URL: http://${ADDR}:${PORT}"
echo "Admin: ${ADMIN_USER} / ${ADMIN_PASSWORD}"
echo "Creds: ${INSTALL_DIR}/admin_credentials.txt"
