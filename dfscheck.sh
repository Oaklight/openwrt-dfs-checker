#!/bin/ash

# Function to get the 5GHz radio name
get_5g_radio_from_file() {
    local wireless_config="/etc/config/wireless"
    local in_block=false
    local radio_name=""

    while IFS= read -r line; do
        # Check if the line starts a wifi-device block
        if [[ "$line" == config\ wifi-device* ]]; then
            in_block=true
            radio_name=$(echo "$line" | awk '{print $3}' | tr -d "'")
        # Check if the line starts another config block or is empty (end of block)
        elif [[ "$line" == config* || -z "$line" ]]; then
            in_block=false
        # Check for 5GHz signals within the wifi-device block
        elif $in_block; then
            # Check for 'option band '5g''
            if [[ "$line" == *option\ band\ \'5g\'* ]]; then
                echo "$radio_name"
                return 0
            fi
            # Check for 'option channel' within 5GHz ranges
            if [[ "$line" == *option\ channel* ]]; then
                local channel=$(echo "$line" | awk '{print $3}' | tr -d "'")
                if [[ $channel -ge 36 && $channel -le 64 ]] ||
                    [[ $channel -ge 100 && $channel -le 144 ]] ||
                    [[ $channel -ge 149 && $channel -le 177 ]]; then
                    echo "$radio_name"
                    return 0
                fi
            fi
        fi
    done <"$wireless_config"

    logger -t "DFS-checker" -p "user.err" "No 5GHz radio found in /etc/config/wireless."
    exit 1
}

get_5g_radio_from_uci() { # triggered a user.err although it found the radio when test standalone
    local radio_name=""

    # Use uci to iterate over all wifi-device sections
    uci -q show wireless | grep 'wireless\.radio[0-9]*=wifi-device' | while read -r line; do
        # Extract the radio name (e.g., radio0)
        radio_name=$(echo "$line" | awk -F'[.=]' '{print $2}')

        # Check if the radio is configured for 5GHz
        band=$(uci -q get "wireless.$radio_name.band")
        channel=$(uci -q get "wireless.$radio_name.channel")

        if [[ "$band" == "5g" ]]; then
            echo "$radio_name"
            return 0
        elif [[ $channel -ge 36 && $channel -le 64 ]] ||
            [[ $channel -ge 100 && $channel -le 144 ]] ||
            [[ $channel -ge 149 && $channel -le 177 ]]; then
            echo "$radio_name"
            return 0
        fi
    done

    logger -t "DFS-checker" -p "user.err" "No 5GHz radio found in uci."
    return 1
}

# Function to switch channel
switch_channel() {
    local radio=$1
    local channel=$2
    uci set "wireless.$radio.channel=$channel"
    uci commit
    if wifi reload; then
        logger -t "DFS-checker" -p "user.info" "Successfully switched $radio to channel $channel"
    else
        logger -t "DFS-checker" -p "user.err" "Failed to switch $radio to channel $channel"
        return 1
    fi
}

# Function to print an iwinfo block
print_iwinfo_block() {
    local block_index=$1
    local current_index=0
    local in_block=false

    # Run iwinfo and process its output
    iwinfo | while IFS= read -r line; do
        # Check if the line starts an info block (interface name)
        if [[ "$line" =~ ^[^[:space:]] ]]; then
            if $in_block; then
                # End of the current block
                current_index=$((current_index + 1))
            fi
            # Start of a new block
            in_block=true
        fi

        # If we're in the desired block, print the line
        if $in_block && [ $current_index -eq $block_index ]; then
            echo "$line"
        fi

        # If we've printed the desired block, exit
        if $in_block && [ $current_index -gt $block_index ]; then
            break
        fi
    done
}

# Function to get the channel from an iwinfo block
get_channel_from_block() {
    local block_index=$1

    # Get the designated info block
    local block=$(print_iwinfo_block "$block_index")

    # Extract the channel number using grep and awk
    local channel=$(echo "$block" | grep -o 'Channel: [0-9]\+' | awk '{print $2}')

    if [ -z "$channel" ]; then
        logger -t "DFS-checker" -p "user.err" "No channel found in the info block."
        exit 1
    fi

    echo "$channel"
}

# Function to get all 5G interfaces on a radio
get_interfaces() {
    local radio=$1
    local interfaces=""
    local block_index=0

    # Loop through all iwinfo blocks
    while true; do
        # Get the current block
        local block=$(print_iwinfo_block "$block_index")
        if [ -z "$block" ]; then
            break # No more blocks
        fi

        # Extract the interface name from the block
        local interface=$(echo "$block" | head -n 1 | awk '{print $1}')

        # Extract the channel from the block
        local channel=$(get_channel_from_block "$block_index")

        # Check if the channel is in the 5GHz range
        if [[ $channel -ge 36 && $channel -le 64 ]] ||
            [[ $channel -ge 100 && $channel -le 144 ]] ||
            [[ $channel -ge 149 && $channel -le 177 ]]; then
            # Add the interface to the list
            interfaces="$interfaces $interface"
        fi

        # Move to the next block
        block_index=$((block_index + 1))
    done

    # Check if any 5G interfaces were found
    if [ -z "$interfaces" ]; then
        logger -t "DFS-checker" -p "user.err" "No 5G interfaces found for radio $radio."
        exit 1
    fi

    # Return the list of 5G interfaces
    echo "$interfaces" | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//'
}

# Function to check if the wireless interface is operational
check_connectivity() {
    local interface=$1

    # Check if the interface exists
    if ! iwinfo "$interface" info &>/dev/null; then
        logger -t "DFS-checker" -p "user.warn" "$interface does not exist or is down."
        return 1
    fi

    # Check if the interface has a valid signal
    local signal=$(iwinfo "$interface" info | grep 'Signal' | awk '{print $2}')
    if [ -z "$signal" ] || [ "$signal" == "unknown" ]; then
        logger -t "DFS-checker" -p "user.warn" "$interface has no signal."
        return 1
    fi

    # If all checks pass, the interface is operational
    echo "$interface is operating normally." # Print to console instead of logging
    return 0
}

# Validate arguments
if [ $# -lt 2 ]; then
    echo "Usage: dfs-checker.sh [channel] [fallback_channel] [backoff_type]"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel to be used if main channel is blocked due to DFS detection"
    echo "  backoff_type:     (Optional) Type of backoff strategy (linear, exp, or fixed, default: fixed)"
    exit 1
fi

channel=$1
fallbackChannel=$2
backoff_type=${3:-"fixed"} # default to fixed

# Get the 5GHz radio
radio=$(get_5g_radio_from_file)
if [ -z "$radio" ]; then
    exit 1
fi

# Get all interfaces on the 5GHz radio
interfaces=$(get_interfaces "$radio")
if [ -z "$interfaces" ]; then
    exit 1
fi

logger -t "DFS-checker" -p "user.warn" "DFS-checker has started. Radio: $radio, channel: $channel, fallback channel: $fallbackChannel"

# Set initial channel
switch_channel "$radio" "$channel"
sleep 120 # Wait for normal WiFi startup

# Initialize backoff variables
initial_sleep=15
retry_interval=10
max_sleep=1800 # half hour
current_sleep=$initial_sleep
max_retries=3
retry_count=0

# Function to calculate backoff
calculate_backoff() {
    local current_sleep=$1
    local initial_sleep=$2
    local max_sleep=$3
    local backoff_type=${4:-"linear"} # default to linear

    if [ "$backoff_type" == "linear" ]; then
        # Fixed increment: add 30 seconds
        current_sleep=$((current_sleep + 30))
    elif [ "$backoff_type" == "exp" ]; then
        # Exponential backoff: 0.5 * 1.24^x * initial_sleep
        local exponent=$(echo "l($current_sleep / $initial_sleep) / l(1.24)" | bc -l | awk '{print int($1)}')
        current_sleep=$(echo "0.5 * 1.24^$exponent * $initial_sleep" | bc -l | awk '{print int($1)}')
    elif [ "$backoff_type" == "fixed" ]; then
        # Fixed backoff: always use the initial_sleep value
        current_sleep=$initial_sleep
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
    operational=false
    for interface in $interfaces; do
        if check_connectivity "$interface"; then
            operational=true
        fi
    done

    if ! $operational; then
        retry_count=$((retry_count + 1))
        if [ $retry_count -ge $max_retries ]; then
            logger -t "DFS-checker" -p "user.err" "Max retries reached. Switching to fallback channel $fallbackChannel for 30 minutes."
            switch_channel "$radio" "$fallbackChannel"
            sleep 1800 # Backoff time for radar detection, at least 30 minutes
            logger -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
            switch_channel "$radio" "$channel"
            sleep 75                     # Allow time for initial DFS scan, must be >60 seconds
            retry_count=0                # Reset retry count after fallback
            current_sleep=$initial_sleep # Reset backoff after a failure
        else
            logger -t "DFS-checker" -p "user.warn" "Connectivity check failed. Retry $retry_count of $max_retries."
            sleep $retry_interval
            # reset current_sleep
            current_sleep=$initial_sleep
        fi
    else
        echo "Radio $radio is operating normally."
        sleep $current_sleep
        # Reset retry count on successful connectivity check
        retry_count=0
        # Calculate backoff based on the specified type
        current_sleep=$(calculate_backoff $current_sleep $initial_sleep $max_sleep "$backoff_type")
    fi
done
