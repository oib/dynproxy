#!/bin/zsh
# Script Version: 10.6
# Description: Dyn DNS update script, checks token, compares IPs, and updates DNS zone if needed.

# Set variables
# ========
TOKEN_FILE="/root/.dynProxy_token"
IP_FILE="/root/.ip.txt"
UPDATE_URL="http://ip.dynproxy.net/update_zone"
LOG_FILE="/var/log/update_zone.log"

# Detect if script is running interactively
if [[ -t 1 ]]; then
    INTERACTIVE=true
else
    INTERACTIVE=false
fi

# Functions
# ========
log() {
    print "$(date '+%Y-%m-%dT%H:%M:%S.%6N'): $1" >> "$LOG_FILE"
}

info() {
    if [[ "$INTERACTIVE" = true ]]; then
        echo "$1"
    fi
}

# Output FastCGI headers if applicable
if [ -t 0 ]; then
    echo "Content-Type: text/plain"
    echo ""
fi

# Ensure the token file exists
if [ ! -f "$TOKEN_FILE" ]; then
    log "ERROR: Token file not found."
    exit 1
fi

# Read the token
TOKEN=$(< "$TOKEN_FILE")
if [ -z "$TOKEN" ]; then
    log "ERROR: Token is empty."
    exit 1
fi

# Log the token retrieval
log "INFO: Token retrieved for update."

# Fetch the current public IP from the external service
IP_CURL=$(curl -s http://ip.dynproxy.net)
if [ -z "$IP_CURL" ]; then
    log "ERROR: Failed to fetch current public IP."
    exit 1
fi

# Ensure the IP file exists
if [ ! -f "$IP_FILE" ]; then
    log "INFO: IP file not found. Creating a new one with current IP."
    echo "$IP_CURL" > "$IP_FILE"
    log "INFO: IP file created with initial IP $IP_CURL."
    info "Initial IP file created with IP: $IP_CURL"
    PREVIOUS_IP="" # Set to empty to force update logic
else
    # Read the previous IP from the IP file
    PREVIOUS_IP=$(< "$IP_FILE")
fi

# Compare the current IP with the previous IP
if [ "$IP_CURL" != "$PREVIOUS_IP" ]; then
    log "INFO: IP has changed from $PREVIOUS_IP to $IP_CURL. Proceeding with DNS update."

    # Log the IP to be updated
    log "INFO: Updating DNS for IP $IP_CURL."

    # Post the token and IP to trigger the DNS zone update
    RESPONSE=$(curl -s -o /tmp/curl_output -w "%{http_code}" -X POST \
                   -H "Content-Type: application/x-www-form-urlencoded" \
                   --data-urlencode "token=$TOKEN" \
                   --data-urlencode "ip=$IP_CURL" \
                   $UPDATE_URL)

    # Log the response and result
    if [ "$RESPONSE" -eq 200 ]; then
        log "SUCCESS: DNS zone update triggered successfully for token $TOKEN and IP $IP_CURL."
        info "DNS zone update triggered successfully"
        # Write the new IP to the IP file
        echo "$IP_CURL" > "$IP_FILE"
    else
        log "ERROR: Failed to trigger DNS zone update for token $TOKEN and IP $IP_CURL. Response code: $RESPONSE. Response body: $(cat /tmp/curl_output)"
        info "Failed to trigger DNS zone update. HTTP response: $RESPONSE"
        exit 1
    fi
else
    log "INFO: IP has not changed. No update needed."
    info "IP has not changed. No update needed."
fi

# Cleanup temporary files
rm -f /tmp/curl_output

