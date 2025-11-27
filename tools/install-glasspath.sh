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
SERVER_ADDRESS="${SERVER_ADDRESS:-0.0.0.0}"
SERVER_PORT="${SERVER_PORT:-8080}"
SERVER_ROOT="${SERVER_ROOT:-/}"
ADVERTISED_HOST=""
ADVERTISED_PORT=""
SERVER_PORT_FALLBACK="${SERVER_PORT_FALLBACK:-5436}"
GLASSPATH_NO_SYSTEMD="${GLASSPATH_NO_SYSTEMD:-}"
GLASSPATH_START_MODE="${GLASSPATH_START_MODE:-auto}"
GLASSPATH_FOREGROUND="${GLASSPATH_FOREGROUND:-}"
USE_SYSTEMD=1
START_MODE="auto"
# Default to latest release unless explicitly pinned.
DEFAULT_GLASSPATH_VERSION="${DEFAULT_GLASSPATH_VERSION:-latest}"
GLASSPATH_VERSION="${GLASSPATH_VERSION:-$DEFAULT_GLASSPATH_VERSION}"
GLASSPATH_TARBALL_URL="${GLASSPATH_TARBALL_URL:-}"

# Basic logging helpers
log() { printf "[glasspath] %s\n" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }
is_true() {
  case "$1" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

# Colors for nicer output
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
NC="\033[0m"

# Prepare temp dir (prefer /var/tmp for space if available)
if [[ -w /var/tmp ]]; then
  TMP_DIR="$(mktemp -d /var/tmp/glasspath.XXXXXX)"
else
  TMP_DIR="$(mktemp -d)"
fi
trap 'rm -rf "$TMP_DIR"' EXIT
log "Using temp dir: $TMP_DIR"

detect_host_ip() {
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return
  fi
  ip="$(ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}')"
  if [[ -n "$ip" ]]; then
    echo "$ip"
    return
  fi
  echo "127.0.0.1"
}

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
  log "Downloading release from ${url}"
  if ! curl -fSL "$url" -o "$out"; then
    die "Failed to download release"
  fi
  if [[ ! -s "$out" ]]; then
    die "Downloaded release is empty: $out"
  fi
}

ensure_user() {
  if [[ "$SERVICE_USER" == "root" ]]; then
    return
  fi
  if (( USE_SYSTEMD == 0 )) && ! command -v useradd >/dev/null 2>&1; then
    log "useradd unavailable without systemd; falling back to root"
    SERVICE_USER="root"
    return
  fi
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

has_systemctl() {
  command -v systemctl >/dev/null 2>&1
}

port_available() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "sport = :$port" | grep -q LISTEN && return 1 || return 0
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | awk '{print $4}' | grep -E ":$port$" >/dev/null && return 1 || return 0
  else
    return 0
  fi
}

write_run_script() {
  local script="/usr/local/bin/${SERVICE_NAME}-run"
  cat <<EOF >"$script"
#!/usr/bin/env bash
set -euo pipefail
CMD="${BIN_PATH} --database ${DATA_DIR}/filebrowser.db --log ${LOG_FILE} --address ${SERVER_ADDRESS} --port ${SERVER_PORT} --root ${SERVER_ROOT}"
echo "[glasspath] starting: \$CMD"
exec \$CMD
EOF
  chmod +x "$script"
  log "Run script written to ${script}"
}

start_without_systemd() {
  local mode="$1"
  local display_host="${2:-}"
  local display_port="${3:-}"
  mkdir -p "$(dirname "$LOG_FILE")" /var/run
  local pidfile="/var/run/${SERVICE_NAME}.pid"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    log "Stopping existing ${SERVICE_NAME} (pid $(cat "$pidfile"))"
    kill "$(cat "$pidfile")" 2>/dev/null || true
    sleep 1
  fi

  local run_port="$SERVER_PORT"
  local cmd=( "$BIN_PATH" --database "${DATA_DIR}/filebrowser.db" --log "${LOG_FILE}" --address "${SERVER_ADDRESS}" --port "${run_port}" --root "${SERVER_ROOT}" )

  if [[ "$mode" == "foreground" ]]; then
    log "Starting ${SERVICE_NAME} without systemd in foreground (logs: ${LOG_FILE})"
    if [[ -n "$display_host" && -n "$display_port" ]]; then
      log "Visit: http://${display_host}:${display_port}"
    fi
    exec "${cmd[@]}"
  fi

  log "Starting ${SERVICE_NAME} without systemd (background, logs: ${LOG_FILE})"
  nohup "${cmd[@]}" >>"${LOG_FILE}" 2>&1 &
  local pid=$!
  sleep 1
  if ! kill -0 "$pid" 2>/dev/null; then
    log "Port ${run_port} unavailable; retrying with fallback ${SERVER_PORT_FALLBACK}"
    cmd=( "$BIN_PATH" --database "${DATA_DIR}/filebrowser.db" --log "${LOG_FILE}" --address "${SERVER_ADDRESS}" --port "${SERVER_PORT_FALLBACK}" --root "${SERVER_ROOT}" )
    nohup "${cmd[@]}" >>"${LOG_FILE}" 2>&1 &
    pid=$!
    run_port="$SERVER_PORT_FALLBACK"
    sleep 1
    if ! kill -0 "$pid" 2>/dev/null; then
      die "Failed to start ${SERVICE_NAME} on both ${SERVER_PORT} and ${SERVER_PORT_FALLBACK}"
    fi
    SERVER_PORT="$run_port"
  fi
  echo $! >"$pidfile"
  log "PID: $(cat "$pidfile") on port ${run_port}"
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
ExecStart=${BIN_PATH} --database ${DATA_DIR}/filebrowser.db --log ${LOG_FILE} --address ${SERVER_ADDRESS} --port ${SERVER_PORT} --root ${SERVER_ROOT}
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
  rm -rf "$tmp_extract"

  # sanity check
  if [[ ! -x "${INSTALL_DIR}/glasspath" ]]; then
    die "Binary not found after extraction at ${INSTALL_DIR}/glasspath"
  fi

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

current_unit_user() {
  local unit="/etc/systemd/system/${SERVICE_NAME}.service"
  if [[ -f "$unit" ]]; then
    awk -F= '/^User=/ {print $2}' "$unit" | head -1
  fi
}

choose_service_user() {
  # Non-interactive: keep existing setting.
  if [[ ! -t 0 ]]; then
    return
  fi

  local existing_user default_user choice
  existing_user="$(current_unit_user)"
  default_user="${SERVICE_USER}"
  [[ -n "$existing_user" ]] && default_user="$existing_user"

  # Build options without duplicates
  local opts=("${default_user}" "custom")
  if [[ "$default_user" != "root" ]]; then
    opts=("${default_user}" "root" "custom")
  fi

  choice="$(prompt_choice "Run service as which user? (default: ${default_user})" "${opts[@]}")"

  case "$choice" in
    "${default_user}")
      SERVICE_USER="$default_user"
      ;;
    "root")
      SERVICE_USER="root"
      ;;
    "custom")
      read -rp "Enter service user: " input_user
      if [[ -n "$input_user" ]]; then
        SERVICE_USER="$input_user"
      else
        SERVICE_USER="$default_user"
      fi
      ;;
    *)
      SERVICE_USER="$default_user"
      ;;
  esac

  log "Service will run as: ${SERVICE_USER}"
}

compute_display_target() {
  local host="$SERVER_ADDRESS"
  local port="$SERVER_PORT"
  if [[ -n "$ADVERTISED_HOST" ]]; then
    host="$ADVERTISED_HOST"
  elif [[ "$SERVER_ADDRESS" == "0.0.0.0" || "$SERVER_ADDRESS" == "" ]]; then
    host="$(detect_host_ip)"
  fi
  if [[ -n "$ADVERTISED_PORT" ]]; then
    port="$ADVERTISED_PORT"
  fi
  printf "%s:%s" "$host" "$port"
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

  if (( USE_SYSTEMD )); then
    write_service_unit
    log "Starting ${SERVICE_NAME}..."
    systemctl start "$SERVICE_NAME"
    log "Done. Service status:"
    systemctl status "$SERVICE_NAME" --no-pager
  else
    read -r display_host display_port <<<"$(compute_display_target)"
    write_run_script
    start_without_systemd "$START_MODE" "$display_host" "$display_port"
    if [[ "$START_MODE" == "background" ]]; then
      log "Started ${SERVICE_NAME} without systemd (background). To run manually: ${SERVICE_NAME}-run"
    fi
  fi

  # Recompute display target in case port/host changed during startup.
  read -r display_host display_port <<<"$(compute_display_target)"
  printf "%b[glasspath]%b Visit: http://%s:%s (open this port in your firewall)\n" "$GREEN" "$NC" "$display_host" "$display_port"
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
  require_cmd uname

  if is_true "$GLASSPATH_NO_SYSTEMD"; then
    USE_SYSTEMD=0
    log "GLASSPATH_NO_SYSTEMD set; skipping systemd setup."
  elif has_systemctl; then
    USE_SYSTEMD=1
  else
    USE_SYSTEMD=0
  fi

  START_MODE="$GLASSPATH_START_MODE"
  [[ -z "$START_MODE" ]] && START_MODE="auto"
  if is_true "$GLASSPATH_FOREGROUND"; then
    START_MODE="foreground"
  fi
  if [[ "$START_MODE" == "auto" ]]; then
    if (( USE_SYSTEMD )); then
      START_MODE="background"
    else
      START_MODE="foreground"
    fi
  fi

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

  if (( USE_SYSTEMD == 0 )) && [[ "$SERVICE_USER" == "glasspath" ]]; then
    log "No systemd detected; defaulting service user to root."
    SERVICE_USER="root"
  fi

  choose_service_user

  if (( USE_SYSTEMD == 0 )) && [[ -t 0 ]]; then
    read -rp "Advertised host for URL (e.g., Docker host IP) []: " input_host
    ADVERTISED_HOST="$input_host"
    read -rp "Advertised port for URL [${SERVER_PORT}]: " input_port
    if [[ -n "$input_port" ]]; then
      ADVERTISED_PORT="$input_port"
    fi
  fi

  BIN_PATH="${INSTALL_DIR}/glasspath"

  # Check port availability; if taken, suggest fallback and prompt for override
  if [[ -t 0 ]]; then
    if ! port_available "$SERVER_PORT"; then
      log "Port ${SERVER_PORT} appears to be in use."
      read -rp "Use fallback port ${SERVER_PORT_FALLBACK}? [Y/n]: " ans_port
      if [[ "$ans_port" =~ ^[Nn] ]]; then
        read -rp "Enter port to use [${SERVER_PORT_FALLBACK}]: " input_port
        if [[ -n "$input_port" ]]; then
          SERVER_PORT="$input_port"
        else
          SERVER_PORT="$SERVER_PORT_FALLBACK"
        fi
      else
        SERVER_PORT="$SERVER_PORT_FALLBACK"
      fi
      log "Using port: ${SERVER_PORT}"
    fi
  fi

  # Confirm install (TTY only).
  if [[ -t 0 ]]; then
    read -rp "Proceed with install? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
      log "Cancelled by user."
      exit 0
    fi
  fi

  do_install_flow "$mode"
}

main "$@"
