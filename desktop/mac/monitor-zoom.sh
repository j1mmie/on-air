#!/usr/bin/env bash
# Monitors Zoom audio and updates the on-air indicator.
#
# Detection: Zoom spawns a dedicated "ZoomAudioService" process only while
# connected to a meeting with audio. Its presence is a reliable signal.
#
# Usage:
#   SERVER_URL=http://192.168.1.1:5000 ./monitor-zoom.sh
#   ZOOM_NAME=myname ./monitor-zoom.sh
#
# Or copy settings.template.toml to settings.toml and source it:
#   export $(grep -v '^#' ../settings.toml | xargs) && ./monitor-zoom.sh

SERVER_URL="${SERVER_URL:-http://192.168.1.1:5000}"
NAME="${ZOOM_NAME:-zoom}"
POLL_INTERVAL=5
RENEW_INTERVAL=60

is_in_meeting() {
    # ZoomAudioService runs only when Zoom has joined meeting audio
    pgrep -x "ZoomAudioService" > /dev/null 2>&1
}

notify() {
    curl -sf "${SERVER_URL}/$1?name=${NAME}" > /dev/null
}

active=false
last_sent=0

echo "Watching Zoom audio (server: ${SERVER_URL}, name: ${NAME})"

while true; do
    now=$(date +%s)

    if is_in_meeting; then
        if [[ "$active" == false || $((now - last_sent)) -ge $RENEW_INTERVAL ]]; then
            if notify on; then
                echo "$(date '+%Y-%m-%dT%H:%M:%S') ON"
            fi
            active=true
            last_sent=$now
        fi
    else
        if [[ "$active" == true ]]; then
            if notify off; then
                echo "$(date '+%Y-%m-%dT%H:%M:%S') OFF"
            fi
            active=false
        fi
    fi

    sleep $POLL_INTERVAL
done
