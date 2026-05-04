#!/usr/bin/env bash
# Monitors Discord voice and Zoom audio, updating the on-air indicator.
# Checks Discord first; skips Zoom if Discord is already active.
#
# Usage:
#   ONAIR_SERVER_URL=http://192.168.1.1:5000 ONAIR_NAME=Ashley ./monitor.sh
#
# List network adapters and their router MAC addresses (useful during setup):
#   ./monitor.sh --list-networks
#
# Or export vars from settings.toml first (keys must use ONAIR_ prefix):
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
#        <key>ONAIR_SERVER_URL</key>
#        <string>http://192.168.4.234:5000</string>
#
#        <key>ONAIR_NAME</key>
#        <string>Ashley</string>
#
#        <key>ONAIR_ROUTER_MAC</key>
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

SERVER_URL="${ONAIR_SERVER_URL:-http://192.168.1.1:5000}"
NAME="${ONAIR_NAME:-desktop}"
ROUTER_MAC="${ONAIR_ROUTER_MAC:-}"
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
    done < <(networksetup -listallhardwareports | awk '/Hardware Port: (Ethernet|Wi-Fi)/{getline; print $2}')
}

# Echoes the matched router MAC and returns 0 if on an applicable network; returns 1 otherwise.
# Returns 1 immediately (no output) when ROUTER_MAC is unset — no filter is configured.
get_applicable_router_mac() {
    [[ -z "$ROUTER_MAC" ]] && return 1

    local current_macs entry mac
    current_macs=$(get_router_macs)

    IFS=',' read -ra entries <<< "$ROUTER_MAC"
    for entry in "${entries[@]}"; do
        entry="${entry// /}"
        if [[ "$entry" == "lan" ]]; then
            local first_mac
            first_mac=$(echo "$current_macs" | head -1)
            [[ -n "$first_mac" ]] && { echo "$first_mac"; return 0; }
        else
            while IFS= read -r mac; do
                [[ "$entry" == "$mac" ]] && { echo "$entry"; return 0; }
            done <<< "$current_macs"
        fi
    done
    return 1
}

is_on_required_network() {
    [[ -z "$ROUTER_MAC" ]] && return 0
    get_applicable_router_mac > /dev/null
}

list_networks() {
    local any=false iface gateway mac
    while IFS= read -r iface; do
        gateway=$(ipconfig getoption "$iface" router 2>/dev/null)
        [[ -z "$gateway" ]] && continue
        mac=$(arp -n "$gateway" 2>/dev/null | awk '{print $4}')
        [[ -z "$mac" ]] && continue
        printf "  %-12s  gateway: %-16s  router mac: %s\n" "$iface" "$gateway" "$mac"
        any=true
    done < <(networksetup -listallhardwareports | awk '/Hardware Port: (Ethernet|Wi-Fi)/{getline; print $2}')
    $any || echo "  (no active network adapters found)"
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

get_active_app() {
    is_discord_active && { echo "Discord"; return; }
    is_zoom_active    && { echo "Zoom"; return; }
}

# ── Helpers ──────────────────────────────────────────────────────────────────

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S') $*"; }

shutdown() { log "Shutting down"; exit 0; }
trap shutdown SIGTERM SIGINT SIGHUP

# ── List networks mode ───────────────────────────────────────────────────────

if [[ "$1" == "--list-networks" ]]; then
    echo "Active network adapters and router MAC addresses:"
    list_networks
    exit 0
fi

# ── Main loop ────────────────────────────────────────────────────────────────

active=false
last_sent=0
network_applicable=""  # empty = unknown; "true" or "false" once determined
detected_app=""        # last app logged as detected

echo "Monitoring Discord and Zoom (server: ${SERVER_URL}, name: ${NAME}, router: ${ROUTER_MAC:-any})"

while true; do
    now=$(date +%s)

    if [[ -n "$ROUTER_MAC" ]]; then
        matched_mac=$(get_applicable_router_mac)
        if [[ -z "$matched_mac" ]]; then
            if [[ "$network_applicable" != "false" ]]; then
                log "No applicable network found. No checks will be done until an applicable network is joined"
                network_applicable="false"
            fi
            sleep $POLL_INTERVAL
            continue
        elif [[ "$network_applicable" != "true" ]]; then
            log "Discovered applicable network with router mac address $matched_mac"
            network_applicable="true"
        fi
    fi

    current_app=$(get_active_app)
    if [[ -n "$current_app" ]]; then
        if [[ "$current_app" != "$detected_app" ]]; then
            log "Detected $current_app usage"
            detected_app="$current_app"
        fi
        if [[ "$active" != true || $((now - last_sent)) -ge $RENEW_INTERVAL ]]; then
            curl -sf "${SERVER_URL}/on?name=${NAME}" > /dev/null \
                && log "Sending ON signal to Display"
            active=true
            last_sent=$now
        fi
    else
        detected_app=""
        if [[ "$active" == true ]]; then
            curl -sf "${SERVER_URL}/off?name=${NAME}" > /dev/null \
                && log "Sending OFF signal to Display"
            active=false
        fi
    fi

    sleep $POLL_INTERVAL
done
