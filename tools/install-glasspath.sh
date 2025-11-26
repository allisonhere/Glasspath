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

fetch_release_json() {
  local tag="$1"
  local json=""
  if [[ "$tag" == "latest" ]]; then
    json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" || true)"
  else
    json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${tag}" || true)"
    if [[ -z "$json" && "$tag" == v* ]]; then
      json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${tag#v}" || true)"
    fi
  fi
  echo "$json"
}

pick_asset_url() {
  local json="$1" arch="$2" preferred="$3"
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

release_json="$(fetch_release_json "$VERSION")"

if [[ "$VERSION" == "latest" && -z "$release_json" ]]; then
  echo "No releases found; falling back to source build (branch main)." >&2
  VERSION="main"
fi

ASSET_URL=""
if [[ -n "$release_json" ]]; then
  ASSET_URL="$(pick_asset_url "$release_json" "$ARCH" "${GLASSPATH_ASSET:-}")"
  if [[ -z "$ASSET_URL" ]]; then
    ASSET_URL="$(echo "$release_json" | grep -oP '"browser_download_url":\s*"\K[^"]+' | head -n1)"
  fi
fi

INSTALL_DIR="/opt/glasspath"
BIN_LINK="/usr/local/bin/glasspath"
SERVICE_NAME="glasspath"
PORT="${PORT:-8080}"
ADDR="${ADDR:-0.0.0.0}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

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
  echo "Attempting to download ${ASSET_URL} ..."
  if [[ -z "$ASSET_URL" ]]; then
    return 1
  fi
  if ! curl -fL "$ASSET_URL" -o "/tmp/glasspath.tar.gz"; then
    return 1
  fi
  sudo rm -rf "$INSTALL_DIR"
  sudo mkdir -p "$INSTALL_DIR"
  sudo tar -C "$INSTALL_DIR" -xzf "/tmp/glasspath.tar.gz"
  local bin_path
  bin_path="$(find "$INSTALL_DIR" -type f -name glasspath | head -n1 || true)"
  if [[ -z "$bin_path" ]]; then
    echo "No glasspath binary found in archive." >&2
    return 1
  fi
  sudo cp "$bin_path" "$INSTALL_DIR/glasspath"
  sudo chmod +x "$INSTALL_DIR/glasspath"
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
  sudo chmod +x "$INSTALL_DIR/glasspath"
}

if ! install_from_release; then
  install_from_source
fi

sudo ln -sf "$INSTALL_DIR/glasspath" "$BIN_LINK"

# set admin password (create a random one if not provided)
if [[ -z "$ADMIN_PASSWORD" ]]; then
  ADMIN_PASSWORD="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)"
fi
sudo "$INSTALL_DIR/glasspath" users update admin --password "$ADMIN_PASSWORD" >/dev/null 2>&1 || true
echo -e "admin\n${ADMIN_PASSWORD}" | sudo tee "${INSTALL_DIR}/admin_credentials.txt" >/dev/null

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
echo "Admin user: admin"
echo "Admin password: ${ADMIN_PASSWORD}"
echo "Credentials saved to ${INSTALL_DIR}/admin_credentials.txt"
