#!/bin/bash
# ==============================================================================
# Hermes Autonomous Agent & 9Router - Setup & Start Script
# ==============================================================================
# This script installs (once) and starts both services. It is idempotent:
# running it again does not duplicate services, does not overwrite an
# existing identity or auth key, and does not reinstall npm packages
# that are already present.
#
# It does NOT install crontab, .bashrc hooks, or systemd units.
# Auto-restart after a VM replacement is provided by a user-authorized
# Muse hook/cron that calls ensure_worker.sh in this repo. See README.md
# and the header of ensure_worker.sh for why that lives outside the VM.
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$HOME/workspace"

echo "=========================================================="
echo "Menyiapkan Hermes Agent & 9Router Infrastructure..."
echo "Direktori: $SCRIPT_DIR"
echo "=========================================================="

mkdir -p "$WORKSPACE"

# 1. Konfigurasi identitas instance jika diberikan parameter (contoh: bash setup.sh Muse-13)
#    Fix: printf, not echo, so no trailing newline is converted into a
#    trailing dash by tr. "Muse-13" must become "worker-muse-13", not
#    "worker-muse-13-".
if [ -n "${1:-}" ]; then
    CLEAN_ID=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-' | sed -e 's/^-*//' -e 's/-*$//')
    printf '%s\n' "$1" > "$WORKSPACE/.vps_name"
    printf 'worker-%s\n' "$CLEAN_ID" > "$WORKSPACE/.worker_id"
    echo "Identitas node disetel: $1 (ID: worker-$CLEAN_ID)"
fi

# 2. Pastikan file autentikasi privat lokal tersedia dengan izin 600.
#    Never overwrite an existing key.
if [ ! -s "$WORKSPACE/.auth_key" ]; then
    node -e "console.log(require('crypto').randomBytes(16).toString('hex'))" > "$WORKSPACE/.auth_key" 2>/dev/null || \
    openssl rand -hex 16 > "$WORKSPACE/.auth_key" 2>/dev/null || \
    echo "hermes-auth-$(date +%s)" > "$WORKSPACE/.auth_key"
fi
chmod 600 "$WORKSPACE/.auth_key" 2>/dev/null || true

# 3. Instal dependensi npm hanya jika belum ada.
echo "Memeriksa dependensi Node.js..."
cd "$SCRIPT_DIR"
if [ ! -x "$SCRIPT_DIR/node_modules/.bin/9router" ]; then
    echo "Menginstal dependensi Node.js..."
    npm install --production --quiet 2>/dev/null || npm install 2>/dev/null || true
else
    echo "Dependensi sudah ada, lewati npm install."
fi

# 4. Start / pastikan kedua service lewat guard yang sama dengan yang
#    dipakai pemantau Muse. Guard ini idempotent dan tidak memakai
#    mode interaktif 9Router (yang keluar sendiri di shell non-interaktif).
#    Tidak ada pkill generik di sini: guard hanya membunuh PID 9Router
#    yang persis, sehingga tidak pernah membunuh shell pemanggilnya.
chmod +x "$SCRIPT_DIR/ensure_worker.sh"
bash "$SCRIPT_DIR/ensure_worker.sh"

echo "=========================================================="
echo "✅ Setup selesai! 9Router dan Hermes Agent dipastikan jalan."
echo "Log Hermes : $WORKSPACE/hermes.log"
echo "Log 9Router: $WORKSPACE/9router.log"
echo "Log Guard  : $WORKSPACE/ensure_worker.log"
echo "=========================================================="
