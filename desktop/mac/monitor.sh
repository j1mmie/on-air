#!/usr/bin/env bash
# Monitors Discord voice and Zoom audio, updating the on-air indicator.
# Checks Discord first; skips Zoom if Discord is already active.
#
# Usage:
#   SERVER_URL=http://192.168.1.1:5000 NAME=Ashley ./monitor.sh
#
# Or export vars from settings.toml first:
#   export $(grep -v '^#' ../settings.toml | xargs) && ./monitor.sh
#
# ── Startup (launchd) ────────────────────────────────────────────────────────
#
# 1. Create ~/Library/LaunchAgents/on-air-monitor.plist with these contents,
#    updating the script path, SERVER_URL, and NAME:
#
#    <?xml version="1.0" encoding="UTF-8"?>
#    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
#      "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
#    <plist version="1.0">
#    <dict>
#      <key>Label</key>
#      <string>on-air-monitor</string>
#
#      <key>ProgramArguments</key>
#      <array>
#        <string>/bin/bash</string>
#        <string>/path/to/on-air/desktop/mac/monitor.sh</string>
#      </array>
#
#      <key>EnvironmentVariables</key>
#      <dict>
#        <key>SERVER_URL</key>
#        <string>http://192.168.4.234:5000</string>
#
#        <key>NAME</key>
#        <string>Ashley</string>
#
#        <key>ROUTER_MAC</key>
#        <string>4c:1:43:8e:76:82</string>
#      </dict>
#
#      <key>RunAtLoad</key>
#      <true/>
#
#      <key>KeepAlive</key>
#      <true/>
#
#      <key>StandardOutPath</key> 
#      <string>/tmp/on-air-monitor.log</string>
#
#      <key>StandardErrorPath</key>
#      <string>/tmp/on-air-monitor.log</string>
#    </dict>
#    </plist>
#
# 2. Load it:
#      launchctl load ~/Library/LaunchAgents/on-air-monitor.plist
#
# To stop:     launchctl unload ~/Library/LaunchAgents/on-air-monitor.plist
# To check:    launchctl list | grep on-air-monitor
# To view log: tail -f /tmp/on-air-monitor.log

SERVER_URL="${SERVER_URL:-http://192.168.1.1:5000}"
NAME="${NAME:-desktop}"
ROUTER_MAC="${ROUTER_MAC:-}"
POLL_INTERVAL=5
RENEW_INTERVAL=60

# ── Network check ────────────────────────────────────────────────────────────

get_router_macs() {
    local iface gateway mac
    while IFS= read -r iface; do
        gateway=$(ipconfig getoption "$iface" router 2>/dev/null)
        [[ -z "$gateway" ]] && continue
        mac=$(arp -n "$gateway" 2>/dev/null | awk '{print $4}')
        [[ -n "$mac" ]] && echo "$mac"
    done < <(networksetup -listallhardwareports | awk '/Device:/{print $2}')
}

is_on_required_network() {
    [[ -z "$ROUTER_MAC" ]] && return 0

    local current_macs entry mac
    current_macs=$(get_router_macs)

    IFS=',' read -ra entries <<< "$ROUTER_MAC"
    for entry in "${entries[@]}"; do
        entry="${entry// /}"
        if [[ "$entry" == "lan" ]]; then
            [[ -n "$current_macs" ]] && return 0
        else
            while IFS= read -r mac; do
                [[ "$entry" == "$mac" ]] && return 0
            done <<< "$current_macs"
        fi
    done
    return 1
}

# ── App detection ────────────────────────────────────────────────────────────

is_discord_active() {
    # Discord voice/video uses WebRTC over UDP; active UDP connections indicate a call
    lsof -i UDP -a -c Discord 2>/dev/null | grep -q "Discord"
}

is_zoom_active() {
    # CptHost is spawned only while Zoom is connected to meeting audio
    pgrep -x "CptHost" > /dev/null
}

is_any_active() {
    is_discord_active || is_zoom_active
}

# ── Main loop ────────────────────────────────────────────────────────────────

active=false
last_sent=0

echo "Monitoring Discord and Zoom (server: ${SERVER_URL}, name: ${NAME}, router: ${ROUTER_MAC:-any})"

while true; do
    now=$(date +%s)

    if ! is_on_required_network; then
        sleep $POLL_INTERVAL
        continue
    fi

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
