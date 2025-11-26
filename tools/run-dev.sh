#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DB_PATH="${DB_PATH:-"$ROOT_DIR/filebrowser.db"}"
BINARY="${BINARY:-"$ROOT_DIR/filebrowser"}"
LOG_DEST="${LOG_DEST:-stdout}"

mkdir -p "$ROOT_DIR/bin"

# Keep any existing DB safe by moving it aside.
if [[ -f "$DB_PATH" ]]; then
  TS="$(date +%Y%m%d_%H%M%S)"
  mv "$DB_PATH" "${DB_PATH}.bak.${TS}"
  echo "Moved existing DB to ${DB_PATH}.bak.${TS}"
fi

echo "Building backend..."
cd "$ROOT_DIR"
go build -o "$BINARY" .

echo "Starting backend (log -> $LOG_DEST, db -> $DB_PATH)..."
exec "$BINARY" --database "$DB_PATH" --log "$LOG_DEST"
