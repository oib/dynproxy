#!/bin/zsh
# Script Version: 05
# Description: Update IP script supporting both IPv4 and IPv6, extracting IP from the request, and checking if token file exists.

# Set variables
# ========
DIRECTORY="/var/www/ip/token"
LOG_FILE="/var/log/update_ip.log"

# Extract the token from the POST data
# ========
read -r post_data
TOKEN=$(echo "$post_data" | grep -oP '(?<=token=)[^&]*')

# Validate that the token was provided
# ========
if [ -z "$TOKEN" ]; then
    echo "Status: 400 Bad Request"
    echo "Content-Type: text/plain"
    echo ""
    echo "Missing token"
    exit 1
fi

# Ensure the token file exists
# ========
TOKEN_FILE="${DIRECTORY}/${TOKEN}.txt"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Status: 403 Forbidden"
    echo "Content-Type: text/plain"
    echo ""
    echo "Token file not found"
    exit 1
fi

# Get the IP address of the client from REMOTE_ADDR
# ========
IP="$REMOTE_ADDR"

# Validate IPv4 or IPv6 address
# ========
if [[ "$IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    IP_TYPE="IPv4"
elif [[ "$IP" =~ ^([a-fA-F0-9]{0,4}:){1,7}[a-fA-F0-9]{1,4}$ ]]; then
    IP_TYPE="IPv6"
else
    echo "Status: 400 Bad Request"
    echo "Content-Type: text/plain"
    echo ""
    echo "Invalid IP format"
    exit 1
fi

# Write the IP to a file using the token as the filename
# ========
echo "$IP" > "$TOKEN_FILE"

# Log the action
# ========
echo "$(date '+%Y-%m-%dT%H:%M:%S.%6N'): $IP_TYPE $IP saved with token $TOKEN" >> "$LOG_FILE"

# Return a success response
# ========
echo "Status: 200 OK"
echo "Content-Type: text/plain"
echo ""
echo "IP updated successfully"

