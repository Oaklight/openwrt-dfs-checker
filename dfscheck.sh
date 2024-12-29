#!/bin/ash

# Function to get the interface name based on device number and ap_index
get_interface() {
    local device_num=$1
    local ap_index=${2:-1} # default to 1
    local radio="radio$device_num"
    local phy=$(uci get wireless.$radio.device 2>/dev/null)
    if [ -z "$phy" ]; then
        phy="phy$device_num"
    fi
    local interfaces=$(iw dev | grep -A 1 "$phy" | grep Interface | awk '{print $2}' | sort -t '-' -k3,3n)
    if [ -z "$interfaces" ]; then
        logger -s -t "DFS-checker" -p "user.err" "No interfaces found for PHY $phy."
        exit 1
    fi
    local num_interfaces=$(echo "$interfaces" | wc -l)
    if [ $ap_index -ge $num_interfaces ]; then
        ap_index=0
        logger -s -t "DFS-checker" -p "user.warn" "Specified ap_index $ap_index out of range, using default index 0."
    fi
    local interface=$(echo "$interfaces" | sed -n "$((ap_index + 1))p")
    if [ -z "$interface" ]; then
        logger -s -t "DFS-checker" -p "user.err" "No interface found for PHY $phy."
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
        return 1
    fi
}

# Function to check if the wireless interface is operational
check_connectivity() {
    local interface=$1

    # Check if the wireless interface exists and is operational
    if ! iw dev "$interface" info &>/dev/null; then
        if iw dev "$interface" info 2>&1 | grep -q 'No such device'; then
            logger -s -t "DFS-checker" -p "user.warn" "$interface does not exist."
        else
            logger -s -t "DFS-checker" -p "user.warn" "$interface is down."
        fi
        return 1
    fi

    # Optional: Check if there are associated clients
    if [ $(iw dev "$interface" station dump | wc -l) -eq 0 ]; then
        logger -s -t "DFS-checker" -p "user.warn" "No clients associated with $interface."
        return 0
    fi

    return 0
}

# Validate arguments
if [ $# -lt 3 ]; then
    echo "Usage: dfs-checker.sh [device] [channel] [fallback_channel] [ap_index]"
    echo "  device:           Numeric (e.g., 0 corresponds to radio0)"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    echo "  ap_index:         Index of the AP interface (default: 1)"
    exit 1
fi

device_num=$1
channel=$2
fallbackChannel=$3
ap_index=${4:-1} # default to 1

interface=$(get_interface "$device_num" "$ap_index")

logger -s -t "DFS-checker" -p "user.warn" "DFS-checker has started. Interface: $interface, channel: $channel, fallback channel: $fallbackChannel"

# Set initial channel
switch_channel "$channel"
sleep 120 # Wait for normal WiFi startup

# Initialize backoff variables
initial_sleep=15
max_sleep=3600 # 1 hour
current_sleep=$initial_sleep
max_retries=3
retry_count=0

# Function to generate a random sleep time within a range
get_random_sleep() {
    local min_sleep=$1
    local max_sleep=$2
    echo $((min_sleep + RANDOM % (max_sleep - min_sleep + 1)))
}

# Function to calculate logarithmic backoff
calculate_backoff() {
    local current_sleep=$1
    local initial_sleep=$2
    local max_sleep=$3

    # Logarithmic backoff: increase sleep time by log2(current_sleep)
    local log_increase=$(echo "l($current_sleep)/l(2)" | bc -l | awk '{print int($1)}')
    current_sleep=$((current_sleep + log_increase))

    # Cap at max_sleep
    if [ $current_sleep -gt $max_sleep ]; then
        current_sleep=$max_sleep
    fi

    echo $current_sleep
}

# Main loop
while true; do
    if ! check_connectivity "$interface"; then
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
            logger -s -t "DFS-checker" -p "user.err" "Max retries reached. Switching to fallback channel $fallbackChannel for 30 minutes."
            switch_channel "$fallbackChannel"
            sleep 1800 # Backoff time for radar detection, at least 30 minutes
            logger -s -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
            switch_channel "$channel"
            sleep 75                     # Allow time for initial DFS scan, must be >60 seconds
            retry_count=0                # Reset retry count after fallback
            current_sleep=$initial_sleep # Reset backoff after a failure
        else
            logger -s -t "DFS-checker" -p "user.warn" "Connectivity check failed. Retry $retry_count of $max_retries."
            sleep $current_sleep
            # Calculate logarithmic backoff
            current_sleep=$(calculate_backoff $current_sleep $initial_sleep $max_sleep)
        fi
    else
        logger -s -t "DFS-checker" -p "user.info" "$interface is operating normally."
        # Generate a random sleep time between half of the current sleep time and the full current sleep time
        random_sleep=$(get_random_sleep $((current_sleep / 2)) $current_sleep)
        sleep $random_sleep
        # Reset retry count on successful connectivity check
        retry_count=0
        # Calculate logarithmic backoff
        current_sleep=$(calculate_backoff $current_sleep $initial_sleep $max_sleep)
    fi
done
