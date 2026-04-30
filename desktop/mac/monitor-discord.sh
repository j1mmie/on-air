#!/usr/bin/env bash
# Monitors Discord voice chat and updates the on-air indicator.
#
# Detection: Discord voice/video uses WebRTC over UDP. When Discord has active
# UDP connections, it is almost certainly in a voice or video call.
#
# Usage:
#   SERVER_URL=http://192.168.1.1:5000 ./monitor-discord.sh
#   DISCORD_NAME=myname ./monitor-discord.sh
#
# Or copy settings.template.toml to settings.toml and source it:
#   export $(grep -v '^#' ../settings.toml | xargs) && ./monitor-discord.sh

SERVER_URL="${SERVER_URL:-http://192.168.1.1:5000}"
NAME="${DISCORD_NAME:-discord}"
POLL_INTERVAL=5
RENEW_INTERVAL=60

is_in_voice() {
    # Discord voice uses WebRTC/UDP; no UDP activity means no active call
    lsof -i UDP -a -c Discord 2>/dev/null | grep -q "Discord"
}

notify() {
    curl -sf "${SERVER_URL}/$1?name=${NAME}" > /dev/null
}

active=false
last_sent=0

echo "Watching Discord voice (server: ${SERVER_URL}, name: ${NAME})"

while true; do
    now=$(date +%s)

    if is_in_voice; then
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
