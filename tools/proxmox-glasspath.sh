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
  RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" || true)"
else
  RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}" || true)"
  if [[ -z "$RELEASE_JSON" && "$VERSION" == v* ]]; then
    RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${VERSION#v}" || true)"
  fi
fi

if [[ -z "$RELEASE_JSON" ]]; then
  echo "No releases found for ${REPO}; publish a tarball or set GLASSPATH_VERSION." >&2
  exit 1
fi

if [[ "$VERSION" == "latest" ]]; then
  VERSION="$(echo "$RELEASE_JSON" | grep -oP '"tag_name":\s*"\K[^"]+' | head -n1)"
fi

pick_asset_url() {
  local json="$1" preferred="$2"
  local urls=()
  mapfile -t urls < <(echo "$json" | grep -oP '"browser_download_url":\s*"\K[^"]+')

  if [[ -n "$preferred" ]]; then
    for u in "${urls[@]}"; do
      if [[ "$u" == *"$preferred"* ]]; then
        echo "$u"; return
      fi
    done
  fi

  for u in "${urls[@]}"; do
    if [[ "$u" == *.tar.gz ]]; then
      echo "$u"; return
    fi
  done

  [[ ${#urls[@]} -gt 0 ]] && echo "${urls[0]}"
}

ASSET_URL="$(pick_asset_url "$RELEASE_JSON" "${GLASSPATH_ASSET:-}")"
if [[ -z "$ASSET_URL" ]]; then
  echo "No suitable release asset found." >&2
  exit 1
fi

INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE_NAME="glasspath"
PORT="${PORT:-8080}"
if [[ -z "${ADDR:-}" ]]; then
  ADDR="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  [[ -z "$ADDR" ]] && ADDR="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -z "$ADDR" ]] && ADDR="0.0.0.0"
fi
ACTION="${ACTION:-install}"
NONINTERACTIVE="${GLASSPATH_NONINTERACTIVE:-false}"

EXISTS=false
if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" || -x "$BIN_LINK" ]]; then
  EXISTS=true
fi

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

if $EXISTS && [[ "$ACTION" == "install" ]] && [[ "$NONINTERACTIVE" != "true" ]] && [[ -t 0 ]]; then
  echo "Glasspath appears to be installed."
  read -r -p "Reinstall (r), Uninstall (u), or Cancel (c)? [r/u/c]: " choice
  case "$choice" in
    [Rr]*) ACTION="install" ;;
    [Uu]*) ACTION="uninstall" ;;
    *) echo "Cancelled."; exit 0 ;;
  esac
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
fi

if $EXISTS && [[ "$ACTION" == "install" ]]; then
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
fi

echo "Downloading ${ASSET_URL} ..."
if ! curl -fL "$ASSET_URL" -o "/tmp/glasspath.tar.gz"; then
  echo "Failed to download ${ASSET_URL}. Ensure release asset exists." >&2
  exit 1
fi

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
tar -C "$INSTALL_DIR" -xzf "/tmp/glasspath.tar.gz"
BIN_PATH="$(find "$INSTALL_DIR" -type f -name glasspath | head -n1 || true)"
if [[ -z "$BIN_PATH" ]]; then
  echo "No glasspath binary found in archive." >&2
  exit 1
fi
cp "$BIN_PATH" "$INSTALL_DIR/glasspath"
chmod +x "$INSTALL_DIR/glasspath"
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
