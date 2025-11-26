#!/usr/bin/env bash
set -euo pipefail

REPO="allisonhere/Glasspath"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) echo "Unsupported arch: $(uname -m)"; exit 1 ;;
esac

ADDR="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
[ -z "$ADDR" ] && ADDR="$(hostname -I | awk '{print $1}')"
[ -z "$ADDR" ] && ADDR="0.0.0.0"
PORT="${PORT:-8080}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-ChangeMeNow123!}"
INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE="/etc/systemd/system/glasspath.service"
ACTION="${ACTION:-install}"
NONINTERACTIVE="${GLASSPATH_NONINTERACTIVE:-false}"

if [[ "$ACTION" == "uninstall" ]]; then
  systemctl stop glasspath 2>/dev/null || true
  systemctl disable glasspath 2>/dev/null || true
  rm -f "$SERVICE" "$BIN_LINK"
  rm -rf "$INSTALL_DIR"
  systemctl daemon-reload
  echo "Glasspath uninstalled and state reset."
  exit 0
fi

EXISTS=false
if [[ -f "$SERVICE" || -x "$BIN_LINK" ]]; then
  EXISTS=true
fi

if $EXISTS && [[ "$ACTION" == "install" ]] && [[ "$NONINTERACTIVE" != "true" ]] && [[ -t 0 ]]; then
  echo "Glasspath appears to be installed."
  read -r -p "Reinstall (r), Uninstall (u), or Cancel (c)? [r/u/c]: " choice
  case "$choice" in
    [Rr]*) ACTION="install" ;;
    [Uu]*) ACTION="uninstall" ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
  if [[ "$ACTION" == "uninstall" ]]; then
    systemctl stop glasspath 2>/dev/null || true
    systemctl disable glasspath 2>/dev/null || true
    rm -f "$SERVICE" "$BIN_LINK"
    rm -rf "$INSTALL_DIR"
    systemctl daemon-reload
    echo "Glasspath uninstalled and state reset."
    exit 0
  fi
fi

RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" || true)"

if [[ -n "${GLASSPATH_URL:-}" ]]; then
  ASSET_URL="$GLASSPATH_URL"
else
  if [[ -n "${GLASSPATH_ASSET:-}" ]]; then
    ASSET_URL="$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -m1 "$GLASSPATH_ASSET" || true)"
  fi
  if [ -z "${ASSET_URL:-}" ]; then
    ASSET_URL="$(echo "$RELEASE_JSON" | grep -oP '"browser_download_url":\s*"\K[^"]+' | grep -m1 -E 'tar\.gz$' || true)"
  fi
fi

if [ -z "${ASSET_URL:-}" ]; then
  echo "Could not find a release tarball for ${REPO}. Set GLASSPATH_URL to the asset URL or GLASSPATH_ASSET to a matching substring." >&2
  exit 1
fi

systemctl stop glasspath 2>/dev/null || true
rm -rf "$INSTALL_DIR" /tmp/gp.tar.gz "$SERVICE"

mkdir -p "$INSTALL_DIR"
curl -fL "$ASSET_URL" -o /tmp/gp.tar.gz
tar -C "$INSTALL_DIR" --strip-components=1 -xzf /tmp/gp.tar.gz || true

BIN="$(find "$INSTALL_DIR" -type f \( -name glasspath -o -perm -111 \) | head -n1)"
chmod +x "$BIN"
ln -sf "$BIN" "$BIN_LINK"

rm -f "$INSTALL_DIR/filebrowser.db"
"$BIN" --database "$INSTALL_DIR/filebrowser.db" users add admin --password "$ADMIN_PASSWORD" --perm.admin --scope "/" >/dev/null 2>&1 || \
"$BIN" --database "$INSTALL_DIR/filebrowser.db" users update admin --password "$ADMIN_PASSWORD" >/dev/null 2>&1 || true
echo -e "admin\n${ADMIN_PASSWORD}" > "${INSTALL_DIR}/admin_credentials.txt"

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
echo "Admin user: admin"
echo "Admin password: ${ADMIN_PASSWORD}"
echo "Credentials saved to ${INSTALL_DIR}/admin_credentials.txt"
