#!/usr/bin/env bash
# Installer for Glasspath (File Browser fork) on Debian/Ubuntu LXCs.
# Supports fresh install, clean reinstall, in-place reinstall, and uninstall.

set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-glasspath}"
SERVICE_USER="${SERVICE_USER:-glasspath}"
INSTALL_DIR="${INSTALL_DIR:-/opt/glasspath}"
DATA_DIR="${DATA_DIR:-/var/lib/glasspath}"
CONFIG_DIR="${CONFIG_DIR:-/etc/glasspath}"
BIN_PATH="${BIN_PATH:-${INSTALL_DIR}/glasspath}"
LOG_FILE="${LOG_FILE:-/var/log/${SERVICE_NAME}.log}"
# Default to latest release unless explicitly pinned.
DEFAULT_GLASSPATH_VERSION="${DEFAULT_GLASSPATH_VERSION:-latest}"
GLASSPATH_VERSION="${GLASSPATH_VERSION:-$DEFAULT_GLASSPATH_VERSION}"
GLASSPATH_TARBALL_URL="${GLASSPATH_TARBALL_URL:-}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log() { printf "[glasspath] %s\n" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "Unsupported architecture: $arch" ;;
  esac
}

build_download_url() {
  local arch tar_version
  arch="$(detect_arch)"
  tar_version="$GLASSPATH_VERSION"

  if [[ -n "$GLASSPATH_TARBALL_URL" ]]; then
    echo "$GLASSPATH_TARBALL_URL"
    return
  fi

  if [[ "$tar_version" == "latest" ]]; then
    tar_version="$(curl -fsSL https://api.github.com/repos/allisonhere/Glasspath/releases/latest | awk -F '\"' '/tag_name/ {print $4; exit}')"
    [[ -z "$tar_version" ]] && die "Could not determine latest release tag"
  fi

  echo "https://github.com/allisonhere/Glasspath/releases/download/${tar_version}/glasspath_${tar_version#v}_linux_${arch}.tar.gz"
}

download_release() {
  local url="$1"
  local out="$2"
  curl -fsSL "$url" -o "$out" || die "Failed to download release"
}

ensure_user() {
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    return
  fi
  log "Creating service user ${SERVICE_USER}"
  useradd --system --no-create-home --shell /usr/sbin/nologin "$SERVICE_USER"
}

stop_service() {
  if systemctl is-enabled --quiet "$SERVICE_NAME" 2>/dev/null || systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    systemctl stop "$SERVICE_NAME" || true
  fi
}

disable_service() {
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
}

remove_service_unit() {
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload || true
}

write_service_unit() {
  cat <<EOF >"/etc/systemd/system/${SERVICE_NAME}.service"
[Unit]
Description=Glasspath File Browser
After=network.target

[Service]
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${BIN_PATH} --database ${DATA_DIR}/filebrowser.db --log ${LOG_FILE}
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${SERVICE_NAME}"
}

install_release() {
  local tarball="$1"
  local arch_dir

  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$(dirname "$LOG_FILE")"

  # Extract into temp, then move contents to INSTALL_DIR root.
  tmp_extract="$(mktemp -d)"
  tar -xzf "$tarball" -C "$tmp_extract"
  # If tarball has a single top-level dir, descend into it.
  first_entry="$(ls -1 "$tmp_extract" | head -1)"
  if [[ -d "$tmp_extract/$first_entry" ]]; then
    mv "$tmp_extract/$first_entry"/* "$INSTALL_DIR"/
  else
    mv "$tmp_extract"/* "$INSTALL_DIR"/
  fi
  rmdir "$tmp_extract" || true

  chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$DATA_DIR" "$CONFIG_DIR" "$(dirname "$LOG_FILE")"
  chmod 0755 "$INSTALL_DIR" "$DATA_DIR"
}

prompt_choice() {
  local prompt="$1"; shift
  local options=("$@")
  local choice
  printf "%s\n" "$prompt" >&2
  local i=1
  for opt in "${options[@]}"; do
    printf "  [%s] %s\n" "$i" "$opt" >&2
    i=$((i+1))
  done
  # If stdin is not a TTY (e.g., piped), default to first option.
  if [[ ! -t 0 ]]; then
    printf "%s\n" "${options[0]}"
    return 0
  fi
  read -rp "> " choice
  # Default to first option on empty input.
  if [[ -z "$choice" ]]; then
    printf "%s\n" "${options[0]}"
    return 0
  fi
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    printf "invalid\n"
    return 0
  fi
  local idx=$((choice-1))
  if (( idx < 0 || idx >= ${#options[@]} )); then
    printf "invalid\n"
    return 0
  fi
  printf "%s\n" "${options[$idx]}"
}

do_install_flow() {
  local mode="$1"
  local url tarball
  url="$(build_download_url)"
  tarball="${TMP_DIR}/glasspath.tar.gz"

  download_release "$url" "$tarball"
  ensure_user

  case "$mode" in
    "clean reinstall")
      stop_service
      rm -rf "$INSTALL_DIR" "$DATA_DIR"
      ;;
    "reinstall over existing")
      stop_service
      ;;
    "fresh install")
      stop_service
      ;;
    *)
      die "Unknown mode: $mode"
      ;;
  esac

  install_release "$tarball"
  write_service_unit
  log "Starting ${SERVICE_NAME}..."
  systemctl start "$SERVICE_NAME"
  log "Done. Service status:"
  systemctl status "$SERVICE_NAME" --no-pager
}

do_uninstall() {
  stop_service
  disable_service
  remove_service_unit
  rm -rf "$INSTALL_DIR" "$CONFIG_DIR" "$DATA_DIR" "$LOG_FILE"
  log "Uninstalled ${SERVICE_NAME}."
}

main() {
  require_cmd curl
  require_cmd tar
  require_cmd systemctl
  require_cmd uname

  local mode="fresh install"

  if [[ -x "$BIN_PATH" || -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
    local choice
    choice="$(prompt_choice "Existing installation detected. Choose an option:" \
      "cancel" \
      "reinstall over existing" \
      "clean reinstall (wipe app + data)" \
      "uninstall")"

    case "$choice" in
      "cancel") log "Cancelled."; exit 0 ;;
      "reinstall over existing") mode="reinstall over existing" ;;
      "clean reinstall (wipe app + data)") mode="clean reinstall" ;;
      "uninstall") do_uninstall; exit 0 ;;
      *) log "Invalid selection, aborting."; exit 1 ;;
    esac
  else
    log "No existing installation detected; proceeding with fresh install."
  fi

  do_install_flow "$mode"
}

main "$@"
