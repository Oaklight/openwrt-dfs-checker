#!/bin/ash

# Function to get the interface name based on device number
get_interface() {
    local device_num=$1
    local radio="radio$device_num"
    local phy=$(uci get wireless.$radio.device 2>/dev/null)
    if [ -z "$phy" ]; then
        phy="phy$device_num"
    fi
    local interface=$(iw dev | grep -A 1 "$phy" | grep Interface | awk '{print $2}')
    if [ -z "$interface" ]; then
        echo "No interface found for PHY $phy."
        exit 1
    fi
    echo "$interface"
}

# Function to switch channel
switch_channel() {
    local channel=$1
    uci set "wireless.radio$device_num.channel=$channel"
    uci commit
    if wifi reload; then
        logger -s -t "DFS-checker" -p "user.info" "Successfully switched to channel $channel"
    else
        logger -s -t "DFS-checker" -p "user.err" "Failed to switch to channel $channel"
    fi
}

# Validate arguments
if [ $# -lt 3 ]; then
    echo "Usage: dfs-checker.sh [device] [channel] [fallback_channel]"
    echo "  device:           Numeric (e.g., 0 corresponds to radio0)"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    exit 1
fi

device_num=$1
channel=$2
fallbackChannel=$3

interface=$(get_interface "$device_num")

logger -s -t "DFS-checker" -p "user.warn" "DFS-checker has started. Interface: $interface, channel: $channel, fallback channel: $fallbackChannel"

# Set initial channel
switch_channel "$channel"
sleep 120 # Wait for normal WiFi startup

# Main loop
while true; do
    if iw dev "$interface" info 2>&1 | grep -q 'No such wireless device'; then
        logger -s -t "DFS-checker" -p "user.warn" "$interface is down, switching to fallback channel $fallbackChannel for 30 minutes."
        switch_channel "$fallbackChannel"
        sleep 1800 # Backoff time for radar detection, at least 30 minutes
        logger -s -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
        switch_channel "$channel"
        sleep 75 # Allow time for initial DFS scan, must be >60 seconds
    else
        logger -s -t "DFS-checker" -p "user.info" "$interface is operating normally."
    fi
    sleep 15 # Check interval
done
