#!/bin/bash

# Telegram Bot Token and Chat ID
BOT_TOKEN="<API TOKEN>" # Placeholder, replace with your actual token
CHAT_ID="<CHAT ID>" # Placeholder, replace with your actual chat ID

# WireGuard Interface Name
WG_INTERFACE="<WIREGUARD INTERFACE>" # Placeholder, replace with your actual wireguard interface. Eg. wg0

# List of WireGuard Peer IPs to monitor
# We'll use these IPs to identify the peers in the wg show output
PEER_IPS=(
    "172.17.2.172/32" # Placeholder, replace with your actual peer's IPs
)

# File to store the last known reachability status of peers
STATUS_FILE="/<FILE PATH>/peer_status.txt" # name the txt file whatever you like

# Handshake threshold in seconds. If the last handshake was longer ago than this, the peer is considered unreachable.
# Adjust this value based on your WireGuard configuration and desired sensitivity.
HANDSHAKE_THRESHOLD=600 # 10 minutes

# Interpret the message text using the MarkdownV2 formatting rules.
PARSE_MODE="MarkdownV2"

# Function to send a Telegram message
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    --data-urlencode chat_id="$CHAT_ID" \
    --data-urlencode text="$message" \
    --data-urlencode parse_mode="$PARSE_MODE" > /dev/null
}

# Load previous status from the file
declare -A previous_status
if [[ -f "$STATUS_FILE" ]]; then
    while IFS='=' read -r ip status; do
        previous_status["$ip"]="$status"
    done < "$STATUS_FILE"
fi

# Get the current timestamp
CURRENT_TIMESTAMP=$(date +%s)

# Get WireGuard status and parse handshake times
# We use 'wg show wg0 dump' for a machine-readable output format
# We filter for lines and extract the IP, last handshake time, and public key
# We use awk to process the output:
# - $4 is the 'allowed ips'. (Replace this with $3 for 'endpoint' IP)
# - $5 is the last handshake time in seconds since the epoch
# - $1 is the public key
# We store this in a temporary file for easier processing
TEMP_WG_STATUS_FILE=$(mktemp)
sudo wg show "$WG_INTERFACE" dump | awk '
    $3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+/ {
        split($4, endpoint, ":"); print endpoint[1]"="$5"="$1
    }' > "$TEMP_WG_STATUS_FILE"

# Initialize current status
declare -A current_status

# Initialize public key
declare -A peer_public_keys

# Process the WireGuard status from the temporary file
while IFS='=' read -r ip handshake_time public_key; do
#    echo "Processing input line: ip='$ip', handshake_time='$handshake_time', public_key='$public_key'" # Added for input check

    # Print the array contents for comparison
#    echo "PEER_IPS array contents: ${PEER_IPS[@]}"

    if [[ " ${PEER_IPS[@]} " =~ " ${ip} " ]]; then
#        echo "IP $ip FOUND in PEER_IPS" # Added for debugging
        peer_public_keys["$ip"]="$public_key" # Store the public key

        if [[ -n "$handshake_time" && "$handshake_time" -ne 0 ]]; then
            time_diff=$((CURRENT_TIMESTAMP - handshake_time))
#            echo "Handshake time is valid. time_diff: $time_diff" # Added for debugging
            if [[ "$time_diff" -le "$HANDSHAKE_THRESHOLD" ]]; then
                current_status["$ip"]="reachable"
#                echo "Status for $ip set to reachable" # Added for debugging
            else
                current_status["$ip"]="unreachable"
#                echo "Status for $ip set to unreachable (time_diff > threshold)" # Added for debugging
            fi
        else
            current_status["$ip"]="unreachable"
#            echo "Status for $ip set to unreachable (invalid handshake time)" # Added for debugging
        fi
#    else
#        echo "IP $ip NOT found in PEER_IPS" # Added for debugging
    fi
done < "$TEMP_WG_STATUS_FILE"

# Remove the temporary file
rm "$TEMP_WG_STATUS_FILE"

# Ensure all monitored IPs have a status (even if not in the wg dump output, they are unreachable)
for peer_ip in "${PEER_IPS[@]}"; do
    if [[ -z "${current_status["$peer_ip"]}" ]]; then
        current_status["$peer_ip"]="unreachable"
    fi
done

# Escape special characters for use in MarkdownV2 formatting
esc_md2() {
    printf '%s' "$1" | sed -e 's/\[/\\\[/g' -e 's/]/\\\]/g' -e 's/(/\\(/g' \
    -e 's/)/\\)/g' -e 's/#/\\#/g' -e 's/+/\\+/g' -e 's/-/\\-/g' \
    -e 's/!/\\!/g' -e 's/|/\\|/g' -e 's/{/\\{/g' -e 's/}/\\}/g' \
    -e 's/</\\</g' -e 's/>/\\>/g' -e 's/\./\\./g' -e 's/:/\\:/g'
}

# Compare current status with previous status and send notifications
for peer_ip in "${PEER_IPS[@]}"; do
    previous="${previous_status["$peer_ip"]}"
    current="${current_status["$peer_ip"]}"
    peer="${peer_ip%%/*}"
#    echo "$peer" # Added for debugging
    public_key="${peer_public_keys["$peer_ip"]:-N/A}" # Get the public key, default value "N/A"
#    echo "$(esc_md2 "$public_key")" # Added for debugging

    # Send a message only when a peer becomes reachable
    if [[ "$current" == "reachable" && "$previous" != "reachable" ]]; then
        message="*[ HANDSHAKE DETECTED! ]*

*${peer}* is now online!
\` $public_key \`"
        msg=$(esc_md2 "$message")
        send_telegram_message "$msg"
    fi
    # Optional message. When a peer becomes unreachable
    if [[ "$current" == "unreachable" && "$previous"  == "reachable" ]]; then
        message="*${peer}* is now offline."
        msg=$(esc_md2 "$message")
        send_telegram_message "$msg"
    fi
done

# Save the current status to the file
> "$STATUS_FILE" # Clear the file
for peer_ip in "${PEER_IPS[@]}"; do
    echo "$peer_ip=${current_status["$peer_ip"]}" >> "$STATUS_FILE"
done

exit 0