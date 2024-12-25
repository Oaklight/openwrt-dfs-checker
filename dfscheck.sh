#!/bin/ash

# Function to switch channel
switch_channel() {
    local channel=$1
    uci set "$radio=$channel"
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
    echo "  device:           Numeric (e.g., 1 corresponds to phy0-ap1)"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    exit 1
fi

# Mapping of device numbers to phy interfaces
declare -A radio_to_phy
radio_to_phy[0]="phy1"
radio_to_phy[1]="phy0"

device_num=$1
channel=$2
fallbackChannel=$3

# Determine the phy interface based on device number
phy_interface=${radio_to_phy[$device_num]}

# Set the interface name
interface="${phy_interface}-ap${device_num}"

# Determine the radio configuration variable
radio="wireless.radio${device_num}.channel"

# Check if the interface exists
if ! iw dev "$interface" info >/dev/null 2>&1; then
    echo "Interface $interface does not exist."
    exit 1
fi

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
