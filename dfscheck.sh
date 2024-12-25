#! /bin/ash

device="wlan$1-1"
radio="wireless.radio$1.channel"
channel="$2"
fallbackChannel="$3"

if [ $# -lt 3 ]; then
    echo "Usage: dfs-checker [device] [channel] [fallback_channel]"
    echo "  device:           Numeric (e.g. 0 translates to wlan0-1)"
    echo "  channel:          Main dfs channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    exit 1
fi

logger -s -t "DFS-checker" -p "user.warn" "DFS-checker has started. Device: $device, channel: $channel, fallback channel: $fallbackChannel"
uci set wireless.radio0.channel="$channel"
uci commit
wifi reload
sleep 120 # Wait for normal wifi startup on boot
while true; do
    iwinfo "$device" info 2>&1 | grep -q 'No such wireless device'
    if [ $? == 0 ]; then
        logger -s -t "DFS-checker" -p "user.warn" "$device is down, switch radio1 channel to $fallbackChannel for 30 minutes."
        uci set wireless.radio0.channel="$fallbackChannel"
        uci commit
        wifi reload
        sleep 1800 # Backoff time for radar detected, at least 30 mins?
        logger -s -t "DFS-checker" -p "user.info" "switch radio1 channel back to $channel"
        uci set wireless.radio0.channel="$channel"
        uci commit
        wifi reload
        sleep 75 # Give time for initial DFS scan, must >60s typ.
    else
        echo "$device is ok"
    fi
    sleep 15 # Check interval
done
