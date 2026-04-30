#!/usr/bin/env bash
# Monitors Discord voice and Zoom audio, updating the on-air indicator for each.
# Each app is tracked independently so they don't interfere with each other.
#
# Usage:
#   SERVER_URL=http://192.168.1.1:5000 ./monitor.sh
#
# Or export vars from settings.toml first:
#   export $(grep -v '^#' ../settings.toml | xargs) && ./monitor.sh

SERVER_URL="${SERVER_URL:-http://192.168.1.1:5000}"
POLL_INTERVAL=5
RENEW_INTERVAL=60

# ── App detection ────────────────────────────────────────────────────────────

is_discord_active() {
    # Discord voice/video uses WebRTC over UDP; active UDP connections indicate a call
    lsof -i UDP -a -c Discord 2>/dev/null | grep -q "Discord"
}

is_zoom_active() {
    # ZoomAudioService is spawned only while Zoom is connected to meeting audio
    pgrep -x "ZoomAudioService" > /dev/null
}

# ── Core ─────────────────────────────────────────────────────────────────────

# check_app <name> <detection-function>
# Tracks per-app state via dynamically-named variables (<name>_active, <name>_sent).
# Sends /on on transition or after RENEW_INTERVAL; sends /off on transition to idle.
check_app() {
    local name="$1" check="$2"
    local active_ref="${name}_active" sent_ref="${name}_sent"

    local now active last_sent
    now=$(date +%s)
    active="${!active_ref:-false}"
    last_sent="${!sent_ref:-0}"

    if "$check"; then
        if [[ "$active" != true || $((now - last_sent)) -ge $RENEW_INTERVAL ]]; then
            curl -sf "${SERVER_URL}/on?name=${name}" > /dev/null \
                && echo "$(date '+%Y-%m-%dT%H:%M:%S') ${name} ON"
            printf -v "$active_ref" true
            printf -v "$sent_ref"   "$now"
        fi
    else
        if [[ "$active" == true ]]; then
            curl -sf "${SERVER_URL}/off?name=${name}" > /dev/null \
                && echo "$(date '+%Y-%m-%dT%H:%M:%S') ${name} OFF"
            printf -v "$active_ref" false
        fi
    fi
}

# ── Main loop ────────────────────────────────────────────────────────────────

echo "Monitoring Discord and Zoom (server: ${SERVER_URL})"

while true; do
    check_app discord is_discord_active
    check_app zoom    is_zoom_active
    sleep $POLL_INTERVAL
done
