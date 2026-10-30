#!/bin/bash
# ==============================================================================
# Hermes Autonomous Agent & 9Router - Setup & Start Script
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$HOME/workspace"

echo "=========================================================="
echo "Menyiapkan Hermes Agent & 9Router Infrastructure..."
echo "Direktori: $SCRIPT_DIR"
echo "=========================================================="

mkdir -p "$WORKSPACE"

# 1. Konfigurasi identitas instance jika diberikan parameter (contoh: bash setup.sh Muse-11)
if [ -n "$1" ]; then
    echo "$1" > "$WORKSPACE/.vps_name"
    CLEAN_ID=$(echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-')
    echo "worker-$CLEAN_ID" > "$WORKSPACE/.worker_id"
    echo "Identitas node disetel: $1 (ID: worker-$CLEAN_ID)"
fi

# 2. Pastikan file autentikasi privat lokal tersedia dengan izin 600
if [ ! -s "$WORKSPACE/.auth_key" ]; then
    node -e "console.log(require('crypto').randomBytes(16).toString('hex'))" > "$WORKSPACE/.auth_key" 2>/dev/null || \
    openssl rand -hex 16 > "$WORKSPACE/.auth_key" 2>/dev/null || \
    echo "hermes-auth-$(date +%s)" > "$WORKSPACE/.auth_key"
fi
chmod 600 "$WORKSPACE/.auth_key" 2>/dev/null || true

# 3. Instal dependensi npm
echo "Menginstal dependensi Node.js..."
cd "$SCRIPT_DIR"
npm install --production --quiet 2>/dev/null || npm install 2>/dev/null || true

# 4. Hentikan instance lama jika ada
pkill -f "9router" 2>/dev/null || true
pkill -f "hermes.js" 2>/dev/null || true
sleep 1

# 5. Jalankan 9Router Service di background (Port 20128)
echo "Menjalankan 9Router local service di port 20128..."
if command -v npx >/dev/null 2>&1; then
    nohup npx 9router --no-browser --port 20128 > "$WORKSPACE/9router.log" 2>&1 &
elif [ -f "$SCRIPT_DIR/node_modules/.bin/9router" ]; then
    nohup "$SCRIPT_DIR/node_modules/.bin/9router" --no-browser --port 20128 > "$WORKSPACE/9router.log" 2>&1 &
fi

# 6. Jalankan Hermes Agent di background
echo "Menjalankan Hermes Agent..."
nohup node "$SCRIPT_DIR/hermes.js" > "$WORKSPACE/hermes.log" 2>&1 &

# 7. Siapkan Autostart Guard persisten di ~/workspace/ensure_worker.sh
cat << 'EOF_GUARD' > "$WORKSPACE/ensure_worker.sh"
#!/bin/bash
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
WORKSPACE="$HOME/workspace"
PKG_DIR="$WORKSPACE/hirmis-na-9-router"
[ -d "$PKG_DIR" ] || PKG_DIR="$WORKSPACE/hermes-9router"

if [ -d "$PKG_DIR" ]; then
    if ! pgrep -f "9router" > /dev/null 2>&1; then
        cd "$PKG_DIR" && nohup npx 9router --no-browser --port 20128 > "$WORKSPACE/9router.log" 2>&1 &
    fi
    if ! pgrep -f "node.*hermes\.js" > /dev/null 2>&1; then
        cd "$PKG_DIR" && nohup node hermes.js > "$WORKSPACE/hermes.log" 2>&1 &
    fi
fi
EOF_GUARD
chmod +x "$WORKSPACE/ensure_worker.sh" 2>/dev/null || true

# Pasang di crontab jika cron tersedia
(crontab -l 2>/dev/null | grep -v "ensure_worker"; echo "*/2 * * * * bash $HOME/workspace/ensure_worker.sh >/dev/null 2>&1") | crontab - 2>/dev/null || true
grep -q "ensure_worker.sh" "$HOME/.bashrc" 2>/dev/null || echo "bash \$HOME/workspace/ensure_worker.sh >/dev/null 2>&1 &" >> "$HOME/.bashrc" 2>/dev/null || true

echo "=========================================================="
echo "✅ Setup selesai! 9Router dan Hermes Agent aktif di latar belakang."
echo "Log Hermes : $WORKSPACE/hermes.log"
echo "Log 9Router: $WORKSPACE/9router.log"
echo "=========================================================="
