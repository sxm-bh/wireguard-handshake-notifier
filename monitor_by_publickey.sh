#!/bin/bash

# Telegram Bot Token and Chat ID
BOT_TOKEN="<API TOKEN>" # Placeholder, replace with your actual token
CHAT_ID="<CHAT ID>" # Placeholder, replace with your actual chat ID

# WireGuard Interface Name
WG_INTERFACE="<WIREGUARD INTERFACE>" # Placeholder, replace with your actual wireguard interface. Eg. wg0

# List of WireGuard Peer public keys to monitor
# We'll use these public keys to identify the peers in the wg show output
PEER_PUBKEY=(
   "kD8x5fXgQw7kL9m4pZT2bVnY6aR3wUoS8fGz1hCjE5t" # Placeholder, replace with your actual peer's public key
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
    while IFS='=' read -r pub_key status; do
        previous_status["$pub_key"]="$status"
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
    $1 ~ /^[A-Za-z0-9+/=]{43,44}$/ {
        split($1, publickey, ":"); print publickey[1]$5 "=" $4
    }' > "$TEMP_WG_STATUS_FILE"

# Initialize current status
declare -A current_status

# Initialize peer ip
declare -A peer_ip

# Process the WireGuard status from the temporary file
while IFS='=' read -r pub_key handshake_time ip; do
#    echo "Processing input line: pub_key='$pub_key', handshake_time='$handshake_time', ip='$ip'" # Added for input check

    # Print the array contents for comparison
#    echo "PEER_PUBKEY array contents: ${PEER_PUBKEY[@]}"

    if [[ " ${PEER_PUBKEY[@]} " =~ " ${pub_key} " ]]; then
#        echo "pub_key $pub_key FOUND in PEER_PUBKEY with $ip" # Added for debugging
        peer_ip["$pub_key"]="$ip" # Store the peer ip

        if [[ -n "$handshake_time" && "$handshake_time" -ne 0 ]]; then
            time_diff=$((CURRENT_TIMESTAMP - handshake_time))
#            echo "Handshake time is valid. time_diff: $time_diff" # Added for debugging
            if [[ "$time_diff" -le "$HANDSHAKE_THRESHOLD" ]]; then
                current_status["$pub_key"]="reachable"
#                echo "Status for $pub_key set to reachable" # Added for debugging
            else
                current_status["$pub_key"]="unreachable"
#                echo "Status for $pub_key set to unreachable (time_diff > threshold)" # Added for debugging
            fi
        else
            current_status["$pub_key"]="unreachable"
#            echo "Status for $pubkey set to unreachable (invalid handshake time)" # Added for debugging
        fi
#    else
#        echo "PUB_KEY $pub_key NOT found in PEER_PUBKEY" # Added for debugging
    fi
done < "$TEMP_WG_STATUS_FILE"

# Remove the temporary file
rm "$TEMP_WG_STATUS_FILE"

# Ensure all monitored public keys have a status (even if not in the wg dump output, they are unreachable)
for peer_pubkey in "${PEER_PUBKEY[@]}"; do
    if [[ -z "${current_status["$peer_pubkey"]}" ]]; then
        current_status["$peer_pubkey"]="unreachable"
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
for peer_pubkey in "${PEER_PUBKEY[@]}"; do
    previous="${previous_status["$peer_pubkey"]}"
    current="${current_status["$peer_pubkey"]}"
    peer_ip="${peer_ip[$peer_pubkey]:-N/A}" # Get the peer ip, default value "N/A"
    peer="${peer_ip%%/*}"
#    echo "$peer" # Added for debugging

    # Send a message only when a peer becomes reachable
    if [[ "$current" == "reachable" && "$previous" != "reachable" ]]; then
        message="*[ HANDSHAKE DETECTED! ]*

*${peer}* is now online!
\` $peer_pubkey \`"
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
for peer_pubkey in "${PEER_PUBKEY[@]}"; do
    echo "$peer_pubkey=${current_status["$peer_pubkey"]}" >> "$STATUS_FILE"
done

exit 0