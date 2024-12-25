#!/bin/ash

# Function to switch channel
switch_channel() {
    local channel=$1
    uci set "$radio=$channel"
    uci commit
    wifi reload
}

# Validate arguments
if [ $# -lt 3 ]; then
    echo "Usage: dfs-checker [device] [channel] [fallback_channel]"
    echo "  device:           Numeric (e.g. 0 translates to wlan0-1)"
    echo "  channel:          Main dfs channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    exit 1
fi

device="wlan$1-1"
radio="wireless.radio$1.channel"
channel="$2"
fallbackChannel="$3"

logger -s -t "DFS-checker" -p "user.warn" "DFS-checker has started. Device: $device, channel: $channel, fallback channel: $fallbackChannel"

# Set initial channel
switch_channel "$channel"
sleep 120 # Wait for normal wifi startup on boot

# Main loop
while true; do
    if iwinfo "$device" info 2>&1 | grep -q 'No such wireless device'; then
        logger -s -t "DFS-checker" -p "user.warn" "$device is down, switching to fallback channel $fallbackChannel for 30 minutes."
        switch_channel "$fallbackChannel"
        sleep 1800 # Backoff time for radar detected, at least 30 mins
        logger -s -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
        switch_channel "$channel"
        sleep 75 # Give time for initial DFS scan, must >60s typ.
    else
        logger -s -t "DFS-checker" -p "user.info" "$device is operating normally."
    fi
    sleep 15 # Check interval
done
