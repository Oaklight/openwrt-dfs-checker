#!/bin/ash

### Core Configuration Functions ###

# Configure channels option
configure_channels_option() {
    local radio=$1
    local main_channel=$2
    local fallback_channels="$3" # Fallback channels as a string

    # Check if channels option already exists
    if ! uci -q get wireless.$radio.channels >/dev/null; then
        logger -t "DFS-checker" "Automatically configuring option channels for $radio"

        # Set the main channel
        logger -t "DFS-checker" "Setting $radio channel to $main_channel"
        uci set wireless.$radio.channel="$main_channel"

        # Set the fallback channels
        uci set wireless.$radio.channels="$fallback_channels"
        uci commit wireless
    else
        # Append new fallback channels (deduplicate)
        current_channels=$(uci -q get wireless.$radio.channels)
        new_channels=$(echo "$current_channels $fallback_channels" | tr ' ' '\n' | awk '!x[$0]++' | tr '\n' ' ')
        uci set wireless.$radio.channels="$new_channels"
        uci commit wireless
    fi
}

### Radio/Interface Discovery Functions ###

# Get the 5GHz radio name from the wireless config file
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
                if validate_channel "$channel"; then
                    echo "$radio_name"
                    return 0
                fi
            fi
        fi
    done <"$wireless_config"

    logger -t "DFS-checker" -p "user.err" "No 5GHz radio found in /etc/config/wireless."
    exit 1
}

# Get the 5GHz radio name from UCI
get_5g_radio_from_uci() {
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
        elif validate_channel "$channel"; then
            echo "$radio_name"
            return 0
        fi
    done

    logger -t "DFS-checker" -p "user.err" "No 5GHz radio found in uci."
    return 1
}

# Get all 5G interfaces on a radio
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

        # Check if the channel is in the 5GHz range using validate_channel
        if validate_channel "$channel"; then
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

### Channel Management Functions ###

# Switch channel
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

# Validate channel
validate_channel() {
    local ch=$1
    # Check if it's a number
    if ! echo "$ch" | grep -Eq '^[0-9]+$'; then
        return 1
    fi

    # Check if it's a valid 5GHz DFS/non-DFS channel
    if [ "$ch" -ge 36 ] && [ "$ch" -le 64 ]; then
        return 0
    elif [ "$ch" -ge 100 ] && [ "$ch" -le 144 ]; then
        return 0
    elif [ "$ch" -ge 149 ] && [ "$ch" -le 177 ]; then
        return 0
    else
        return 1
    fi
}

### Connectivity and Signal Check Functions ###

# Get client count
get_client_count() {
    local interface=$1
    local client_count=0
    local last_warn_file="/tmp/dfs_checker_last_warn_$interface"
    local last_warn_time=0

    # Read the last warning time from the file
    if [ -f "$last_warn_file" ]; then
        last_warn_time=$(cat "$last_warn_file")
    fi

    # Use iw command to get client count
    client_count=$(iw dev "$interface" station dump 2>/dev/null | grep -c "Station")
    if [ $? -ne 0 ]; then
        local current_time=$(date +%s)
        if [ $((current_time - last_warn_time)) -gt 300 ]; then # Only log every 5 minutes
            logger -t "DFS-checker" -p user.warn "Failed to get client count for $interface"
            echo "$current_time" >"$last_warn_file"
        fi
        echo 0
        return
    fi

    echo "$client_count"
}

# Check connectivity and signal strength
check_connectivity() {
    local interface=$1
    local last_state_file="/tmp/dfs_checker_last_state_$interface"
    local last_state=""

    # Read the last state from the file
    if [ -f "$last_state_file" ]; then
        last_state=$(cat "$last_state_file")
    fi

    # Basic check: whether interface exists?
    if ! iwinfo "$interface" info &>/dev/null; then
        if [ "$last_state" != "down" ]; then
            logger -t "DFS-checker" -p "user.warn" "$interface does not exist or is down."
            echo "down" >"$last_state_file"
        fi
        return 1
    fi

    # Signal detection logic
    local signal=$(iwinfo "$interface" info | awk '/Signal/ {print $2}')
    if [ -z "$signal" ] || [ "$signal" == "unknown" ]; then
        local client_count=$(get_client_count "$interface")

        # Key improvement: whether there is a client connected?
        if [ "$client_count" -gt 0 ]; then
            if [ "$last_state" != "signal_lost_with_clients" ]; then
                logger -t "DFS-checker" -p "user.warn" "$interface: Signal lost with $client_count clients (DFS suspected)."
                echo "signal_lost_with_clients" >"$last_state_file"
            fi
            return 1
        else
            if [ "$last_state" != "signal_unknown_no_clients" ]; then
                logger -t "DFS-checker" -p "user.info" "$interface: Signal unknown but no clients (normal)."
                echo "signal_unknown_no_clients" >"$last_state_file"
            fi
            return 0 # Key changes: if no client is connected, return as normal
        fi
    fi

    # Handling normal signal
    if [ "$last_state" != "normal" ]; then
        logger -t "DFS-checker" -p "user.info" "$interface: Normal operation (Signal: $signal)."
        echo "normal" >"$last_state_file"
    fi
    return 0
}

### Utility Functions ###

# Print an iwinfo block
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

# Get the channel from an iwinfo block
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

# Calculate backoff time
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

### Main Script Logic ###

# Validate arguments
if [ $# -lt 2 ]; then
    echo "Usage: dfs-checker.sh [channel] [fallback_channel1] [fallback_channel2] ... [fallback_channelN] [backoff_type]"
    echo "  channel:          Main DFS channel to be used"
    echo "  fallback_channel: Secondary channel(s) to be used if main channel is blocked due to DFS detection"
    echo "  backoff_type:     (Optional) Type of backoff strategy (linear, exp, or fixed, default: fixed)"
    exit 1
fi

# Main channel
channel=$1
fallback_channels="" # Fallback channels stored as a string
backoff_type="fixed" # Default backoff strategy

# Parse fallback channels and backoff strategy
shift 1 # Remove the first argument (main channel)
while [ $# -gt 0 ]; do
    if echo "$1" | grep -Eq '^(linear|exp|fixed)$'; then
        backoff_type=$1 # If the argument is a backoff strategy, assign it and break
        break
    else
        # Append fallback channels to the string
        fallback_channels="$fallback_channels $1"
        shift 1
    fi
done

# Remove leading and trailing spaces from fallback channels
fallback_channels=$(echo "$fallback_channels" | xargs)

# Validate main channel
if ! validate_channel $channel; then
    echo "ERROR: Invalid main channel specified, must be a 5GHz DFS/non-DFS channel"
    exit 2
fi

# Validate fallback channels
for fb_ch in $fallback_channels; do
    if ! validate_channel $fb_ch; then
        echo "ERROR: Invalid fallback channel specified: $fb_ch, must be a 5GHz DFS/non-DFS channel"
        exit 2
    fi
done

# Get the 5GHz radio
radio=$(get_5g_radio_from_file)
if [ -z "$radio" ]; then
    exit 1
fi

# Log the start of DFS-checker with main and fallback channels
logger -t "DFS-checker" -p "user.warn" "DFS-checker has started. Radio: $radio, channel: $channel, fallback channels: $fallback_channels"

# Configure channels
configure_channels_option "$radio" "$channel" "$fallback_channels"

# Wait for normal WiFi startup
sleep 120

# Initialize backoff variables
initial_sleep=15
retry_interval=10
max_sleep=1800 # half hour
current_sleep=$initial_sleep
max_retries=3
retry_count=0

# Get all interfaces on the 5GHz radio
interfaces=$(get_interfaces "$radio")
if [ -z "$interfaces" ]; then
    exit 1
fi

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
            logger -t "DFS-checker" -p "user.err" "Max retries reached. Switching to fallback channel $fallback_channels for 30 minutes."
            switch_channel "$radio" "$fallback_channels"
            sleep 1800 # Backoff time for radar detection, at least 30 minutes
            logger -t "DFS-checker" -p "user.info" "Switching back to main channel $channel"
            switch_channel "$radio" "$channel"
            sleep 75                     # Allow time for initial DFS scan, must be >60 seconds
            retry_count=0                # Reset retry count after fallback
            current_sleep=$initial_sleep # Reset backoff after a failure
        else
            logger -t "DFS-checker" -p "user.warn" "Connectivity check failed. Retry $retry_count of $max_retries."
            sleep $retry_interval
            # Reset current_sleep
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
