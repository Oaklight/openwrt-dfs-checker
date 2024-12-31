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
        logger -t "DFS-checker" -p "user.err" "No interfaces found for PHY $phy."
        exit 1
    fi
    local num_interfaces=$(echo "$interfaces" | wc -l)
    if [ $ap_index -ge $num_interfaces ]; then
        ap_index=0
        logger -t "DFS-checker" -p "user.warn" "Specified ap_index $ap_index out of range, using default index 0."
    fi
    local interface=$(echo "$interfaces" | sed -n "$((ap_index + 1))p")
    if [ -z "$interface" ]; then
        logger -t "DFS-checker" -p "user.err" "No interface found for PHY $phy."
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
        logger -t "DFS-checker" -p "user.info" "Successfully switched to channel $channel"
    else
        logger -t "DFS-checker" -p "user.err" "Failed to switch to channel $channel"
        return 1
    fi
}

# Function to check if the wireless interface is operational
check_connectivity() {
    local interface=$1

    # Check if the wireless device exists
    if ! iwinfo "$interface" info &>/dev/null; then
        if iwinfo "$interface" info 2>&1 | grep -q 'No such wireless device'; then
            logger -t "DFS-checker" -p "user.warn" "$interface does not exist."
        else
            logger -t "DFS-checker" -p "user.warn" "$interface is down or inaccessible."
        fi
        return 1
    fi

    # Check if the interface has a valid signal
    local signal=$(iwinfo "$interface" info | grep 'Signal' | awk '{print $2}')
    if [ -z "$signal" ] || [ "$signal" == "unknown" ]; then
        logger -t "DFS-checker" -p "user.warn" "$interface has no signal."
        return 1
    fi

    # Check if the interface is transmitting (optional)
    local tx_power=$(iwinfo "$interface" info | grep 'Tx-Power' | awk '{print $2}')
    if [ -z "$tx_power" ] || [ "$tx_power" == "unknown" ]; then
        logger -t "DFS-checker" -p "user.warn" "$interface is not transmitting."
        return 1
    fi

    # If all checks pass, the interface is operational
    logger -t "DFS-checker" -p "user.info" "$interface is operating normally."
    return 0
}

# Validate arguments
if [ $# -lt 3 ]; then
    echo "Usage: dfs-checker.sh [device] [channel] [fallback_channel] [ap_index] [backoff_type]"
    echo "  device:           Numeric (e.g., 0 corresponds to radio0)"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    echo "  ap_index:         Index of the AP interface (default: 1)"
    echo "  backoff_type:     Type of backoff strategy (linear or exp, default: linear)"
    exit 1
fi

device_num=$1
channel=$2
fallbackChannel=$3
ap_index=${4:-1}            # default to 1
backoff_type=${5:-"linear"} # default to linear

interface=$(get_interface "$device_num" "$ap_index")

logger -t "DFS-checker" -p "user.warn" "DFS-checker has started. Interface: $interface, channel: $channel, fallback channel: $fallbackChannel"

# Set initial channel
switch_channel "$channel"
sleep 120 # Wait for normal WiFi startup

# Initialize backoff variables
initial_sleep=15
max_sleep=1800 # half hour
current_sleep=$initial_sleep
max_retries=3
retry_count=0

# Function to calculate logarithmic backoff
calculate_backoff() {
    local current_sleep=$1
    local initial_sleep=$2
    local max_sleep=$3
    local backoff_type=${4:-"linear"} # 默认使用线性退避

    if [ "$backoff_type" == "linear" ]; then
        # 固定增量：每次增加30秒
        current_sleep=$((current_sleep + 30))
    elif [ "$backoff_type" == "exp" ]; then
        # 指数退避：0.5 * 1.24^x * initial_sleep
        local exponent=$(echo "l($current_sleep / $initial_sleep) / l(1.24)" | bc -l | awk '{print int($1)}')
        current_sleep=$(echo "0.5 * 1.24^$exponent * $initial_sleep" | bc -l | awk '{print int($1)}')
    else
        echo "Invalid backoff type. Using linear backoff."
        current_sleep=$((current_sleep + 30))
    fi

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
            logger -t "DFS-checker" -p "user.err" "Max retries reached. Switching to fallback channel $fallbackChannel for 30 minutes."
            switch_channel "$fallbackChannel"
            sleep 1800 # Backoff time for radar detection, at least 30 minutes
            logger -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
            switch_channel "$channel"
            sleep 75                     # Allow time for initial DFS scan, must be >60 seconds
            retry_count=0                # Reset retry count after fallback
            current_sleep=$initial_sleep # Reset backoff after a failure
        else
            logger -t "DFS-checker" -p "user.warn" "Connectivity check failed. Retry $retry_count of $max_retries."
            sleep $current_sleep
            # Calculate backoff based on the specified type
            current_sleep=$(calculate_backoff $current_sleep $initial_sleep $max_sleep "$backoff_type")
        fi
    else
        logger -t "DFS-checker" -p "user.info" "$interface is operating normally."
        sleep $current_sleep
        # Reset retry count on successful connectivity check
        retry_count=0
        # Calculate backoff based on the specified type
        current_sleep=$(calculate_backoff $current_sleep $initial_sleep $max_sleep "$backoff_type")
    fi
done
