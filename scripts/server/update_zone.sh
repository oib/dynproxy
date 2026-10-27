#!/bin/zsh
# Script Version: 12.4
# Description: Dyn DNS update script, checks token and updates DNS zone.

# Set variables
DIRECTORY="/var/www/ip/token"
LOG_FILE="/var/log/dynProxy.log"
TOKEN_DNS_ZONE_FILE="/etc/bind/tokendnszone.conf"
NSUPDATE_SERVER="127.0.0.1"
DEBUG=true

log() {
    local message="$1"
    echo "$(date '+%Y-%m-%dT%H:%M:%S.%6N'): $message" >> "$LOG_FILE"
    if $DEBUG; then echo "$message"; fi
}

log_debug() {
    if $DEBUG; then log "$1"; fi
}

# Output FastCGI headers
# These must be the first lines output by the script
echo "Content-Type: text/plain"
echo ""

log "Starting DNS update script."

# Extract the token and IP from the POST data
read -r post_data
log "Received POST data: $post_data"
TOKEN=$(echo "$post_data" | grep -oP '(?<=token=)[a-zA-Z0-9_-]+')
NEW_IP=$(echo "$post_data" | grep -oP '(?<=ip=)[0-9.]+')

if [ -z "$TOKEN" ]; then
    echo "Status: 400 Bad Request"
    echo "Missing token"
    log "Missing token"
    exit 1
fi

if [ -z "$NEW_IP" ]; then
    echo "Status: 400 Bad Request"
    echo "Missing IP"
    log "Missing IP in POST data"
    exit 1
fi

log "Token $TOKEN validated successfully."
log "New IP extracted from POST data: $NEW_IP"

TOKEN_FILE="${DIRECTORY}/${TOKEN}.txt"
if [ ! -f "$TOKEN_FILE" ]; then
    echo "Status: 403 Forbidden"
    echo "Token file not found"
    log "Token file not found for token $TOKEN"
    exit 1
fi

log "Token file found for token $TOKEN."

CLIENT_INFO=$(grep -m 1 "^$TOKEN," "$TOKEN_DNS_ZONE_FILE")
log_debug "CLIENT_INFO: $CLIENT_INFO"

if [ -z "$CLIENT_INFO" ]; then
    echo "Status: 403 Forbidden"
    echo "Token mapping not found in DNS zone configuration"
    log "Token mapping not found for token $TOKEN"
    exit 1
fi

log "Token mapping found for token $TOKEN."

DOMAIN=$(echo "$CLIENT_INFO" | cut -d',' -f2)
ZONE_FILE=$(echo "$CLIENT_INFO" | cut -d',' -f3)

if [ ! -f "$ZONE_FILE" ]; then
    echo "Status: 404 Not Found"
    echo "Zone file $ZONE_FILE not found"
    log "Zone file $ZONE_FILE not found for domain $DOMAIN"
    exit 1
fi

log "Zone file $ZONE_FILE found for domain $DOMAIN."

CURRENT_IP=$(cat "$TOKEN_FILE" | tr -d '[:space:]')
log "Current IP from token file: $CURRENT_IP"

SHORT_DOMAIN="${DOMAIN%%.*}"
ZONE_IP=$(awk -v origin="dynproxy.net." -v domain="$DOMAIN" '
    BEGIN {FS="[ \t]+"}
    $1 == substr(domain, 1, index(domain, ".") - 1) && $2 == "A" {print $3}
    $1 == domain && $2 == "A" {print $3}
' "$ZONE_FILE" | tr -d '[:space:]')

if [ -z "$ZONE_IP" ]; then
    log "Failed to extract ZONE_IP for domain $DOMAIN from zone file $ZONE_FILE. Ensure the A record exists."
    echo "Status: 500 Internal Server Error"
    echo "Failed to extract ZONE_IP for domain $DOMAIN"
    exit 1
fi

log "Extracted ZONE_IP for $DOMAIN: $ZONE_IP"

if [ "$NEW_IP" = "$ZONE_IP" ]; then
    echo "IP in zone file is already up-to-date. No update needed."
    log "IP for $DOMAIN is already up-to-date. No update needed."
    exit 0
fi

log "IP has changed for $DOMAIN. Proceeding with DNS update."

nsupdate_output=$(nsupdate <<EOF 2>&1
server $NSUPDATE_SERVER
zone ${DOMAIN#*.}
update delete $DOMAIN A
update add $DOMAIN 604800 A $NEW_IP
send
EOF
)

if [ $? -ne 0 ]; then
    echo "Status: 500 Internal Server Error"
    echo "Failed to update DNS for $DOMAIN"
    log "Failed to update DNS for $DOMAIN. nsupdate output: $nsupdate_output"
    exit 1
fi

log "DNS updated successfully for $DOMAIN to IP $NEW_IP"

echo "$NEW_IP" > "$TOKEN_FILE"
if [ $? -eq 0 ]; then
    log "Token file updated with new IP: $NEW_IP"
else
    log "Failed to update token file: $TOKEN_FILE"
fi

echo "IP updated successfully for $DOMAIN"

