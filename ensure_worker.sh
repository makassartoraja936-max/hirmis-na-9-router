#!/bin/bash
# ==============================================================================
# ensure_worker.sh - Idempotent guard for Hermes + 9Router
# ==============================================================================
# What this script DOES:
#   - Starts Hermes (node hermes.js) only if it is not already running.
#   - Starts 9Router in tray mode, bound to 127.0.0.1:20128, only if
#     http://127.0.0.1:20128/v1/models does not answer.
#   - Installs npm dependencies only if node_modules is missing.
#   - Appends a timestamped line to ~/workspace/ensure_worker.log.
#
# What this script does NOT do, on purpose:
#   - It does NOT install crontab, .bashrc hooks, or systemd units.
#   - It does NOT download code, change identity files, or overwrite
#     ~/workspace/.auth_key if it already exists.
#   - It does NOT log proxy credentials or any secret.
#
# Why no crontab/systemd here?
#   A VM replacement wipes processes, /var (crontab) and /etc (systemd),
#   and only ~/ survives. A hidden VM-side persistence mechanism would
#   also look suspicious to an audit. The durable trigger lives OUTSIDE
#   the VM, in Muse itself: a user-authorized Muse hook/cron that calls
#   this transparent script. That schedule is visible in Muse, survives
#   VM replacement, and only ever runs this file. See README.md.
#
# This script is safe to run repeatedly. It never starts a second copy
# of a service that is already healthy, and concurrent runs are
# serialized with flock.
# ==============================================================================

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$HOME/workspace"
ROUTER_HOST="127.0.0.1"
ROUTER_PORT="20128"
LOG_FILE="$WORKSPACE/ensure_worker.log"
LOCK_FILE="$WORKSPACE/.ensure_worker.lock"

mkdir -p "$WORKSPACE"
exec 200>"$LOCK_FILE" || exit 1
flock -n 200 || { echo "$(date -Is) ensure_worker: another run is active, exiting" >> "$LOG_FILE"; exit 0; }

log() { echo "$(date -Is) ensure_worker: $*" >> "$LOG_FILE"; }

# --- Prerequisites ---------------------------------------------------------
if [ ! -f "$WORKSPACE/.vps_name" ] || [ ! -f "$WORKSPACE/.worker_id" ]; then
    log "WARNING: identity files missing in $WORKSPACE, continuing with what hermes.js can read"
fi

if [ ! -s "$WORKSPACE/.auth_key" ]; then
    node -e "console.log(require('crypto').randomBytes(16).toString('hex'))" > "$WORKSPACE/.auth_key" 2>/dev/null || \
    openssl rand -hex 16 > "$WORKSPACE/.auth_key" 2>/dev/null || \
    echo "hermes-auth-$(date +%s)" > "$WORKSPACE/.auth_key"
fi
chmod 600 "$WORKSPACE/.auth_key" 2>/dev/null || true

if [ ! -x "$SCRIPT_DIR/node_modules/.bin/9router" ]; then
    log "node_modules missing, running npm install"
    (cd "$SCRIPT_DIR" && npm install --production --quiet 2>/dev/null || npm install 2>/dev/null || true)
fi

# --- Helpers ---------------------------------------------------------------
# NOTE on patterns: the patterns below match the real service command
# lines ("node hermes.js", "node .../.bin/9router", "npm exec 9router").
# They do NOT match this script's own command line, which is just
# "bash .../ensure_worker.sh", so this script can never kill itself
# the way a generic pkill -f "9router" / "hermes.js" could.
hermes_running() {
    pgrep -f 'node hermes[.]js' >/dev/null 2>&1 || \
    pgrep -f 'node .*/hermes[.]js' >/dev/null 2>&1
}

router_healthy() {
    curl -s -m 5 "http://${ROUTER_HOST}:${ROUTER_PORT}/v1/models" >/dev/null 2>&1
}

router_pids() {
    # PIDs of the real 9Router processes only, not this script.
    pgrep -f 'node .*/\.bin/9router' 2>/dev/null
    pgrep -f 'npm exec 9router' 2>/dev/null
}

start_hermes() {
    log "starting hermes.js"
    # No subshell here, on purpose. A "(cd ... && nohup ... &)" subshell
    # stays alive as the background job's parent and keeps the flock
    # fd open, so every later guard run would wrongly report
    # "another run is active". Instead: absolute path, no cd, close
    # fd 200 in the child (200>&-), redirect stdin from /dev/null,
    # and disown so this script can exit without waiting.
    nohup node "$SCRIPT_DIR/hermes.js" >> "$WORKSPACE/hermes.log" 2>&1 200>&- < /dev/null &
    disown || true
}

start_router() {
    log "starting 9router in tray mode on ${ROUTER_HOST}:${ROUTER_PORT}"
    if [ -x "$SCRIPT_DIR/node_modules/.bin/9router" ]; then
        nohup "$SCRIPT_DIR/node_modules/.bin/9router" --tray --skip-update --no-browser --port "$ROUTER_PORT" --host "$ROUTER_HOST" >> "$WORKSPACE/9router.log" 2>&1 200>&- < /dev/null &
    else
        nohup npx 9router --tray --skip-update --no-browser --port "$ROUTER_PORT" --host "$ROUTER_HOST" >> "$WORKSPACE/9router.log" 2>&1 200>&- < /dev/null &
    fi
    disown || true
}

# --- Hermes ----------------------------------------------------------------
if hermes_running; then
    log "hermes already running, skipping"
else
    start_hermes
fi

# --- 9Router ---------------------------------------------------------------
if router_healthy; then
    log "9router already healthy on ${ROUTER_HOST}:${ROUTER_PORT}, skipping"
else
    # An unhealthy router process may still hold the port. Kill only
    # the exact router PIDs found above, never a generic pattern.
    for pid in $(router_pids); do
        # Never kill ourselves or our parent shell.
        if [ "$pid" != "$$" ] && [ "$pid" != "$PPID" ]; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    sleep 2
    start_router
    # Wait up to 30s for a healthy response. A failure here is logged,
    # not fatal: the next guard run (or Muse hook poll) will retry.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if router_healthy; then
            log "9router healthy"
            break
        fi
        sleep 3
    done
    router_healthy || log "WARNING: 9router not healthy after start, will retry next run"
fi

log "done"
