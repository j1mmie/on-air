#!/usr/bin/env bash
# Monitors Discord voice and Zoom audio, updating the on-air indicator.
# Checks Discord first; skips Zoom if Discord is already active.
#
# Usage:
#   SERVER_URL=http://192.168.1.1:5000 NAME=Ashley ./monitor.sh
#
# Or export vars from settings.toml first:
#   export $(grep -v '^#' ../settings.toml | xargs) && ./monitor.sh

SERVER_URL="${SERVER_URL:-http://192.168.1.1:5000}"
NAME="${NAME:-desktop}"
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

is_any_active() {
    is_discord_active || is_zoom_active
}

# ── Main loop ────────────────────────────────────────────────────────────────

active=false
last_sent=0

echo "Monitoring Discord and Zoom (server: ${SERVER_URL}, name: ${NAME})"

while true; do
    now=$(date +%s)

    if is_any_active; then
        if [[ "$active" != true || $((now - last_sent)) -ge $RENEW_INTERVAL ]]; then
            curl -sf "${SERVER_URL}/on?name=${NAME}" > /dev/null \
                && echo "$(date '+%Y-%m-%dT%H:%M:%S') ON"
            active=true
            last_sent=$now
        fi
    else
        if [[ "$active" == true ]]; then
            curl -sf "${SERVER_URL}/off?name=${NAME}" > /dev/null \
                && echo "$(date '+%Y-%m-%dT%H:%M:%S') OFF"
            active=false
        fi
    fi

    sleep $POLL_INTERVAL
done
