#!/bin/bash
# Version 02.1
# Script to create a new client DNS record in the zone and generate a token.
# This script is intended for the primary DNS server in the dynProxy setup.

set -e

# Configuration
TOKENS_DIR="/var/www/ip/token"
KEY_FILE="/etc/bind/nsupdate_key.conf"
DNS_SERVER="127.0.0.1"  # Update with your DNS server's IP if different
# TTL is not explicitly set here as the zone file default is used  # Time to live for the DNS record

# Functions
function usage() {
    echo "Usage: $0"
    exit 1
}

function check_prerequisites() {
    if [[ ! -d $TOKENS_DIR ]]; then
        echo "Error: Tokens directory $TOKENS_DIR does not exist."
        exit 1
    fi

    if [[ ! -f $KEY_FILE ]]; then
        echo "Error: TSIG key file $KEY_FILE does not exist."
        exit 1
    fi
}

# Prompt for inputs
read -p "Enter the subdomain: " SUBDOMAIN
read -p "Enter the domain: " DOMAIN

FULL_DOMAIN="$SUBDOMAIN.$DOMAIN."

# Check prerequisites
check_prerequisites

# Generate token
TOKEN=$(openssl rand -hex 16)
TOKEN_FILE="$TOKENS_DIR/$TOKEN.txt"

if [[ -f $TOKEN_FILE ]]; then
    echo "Error: Token file for $TOKEN already exists."
    exit 1
fi

touch "$TOKEN_FILE"
chmod 644 "$TOKEN_FILE"
chown www-data:www-data "$TOKEN_FILE"

echo "Generated token file for $FULL_DOMAIN: $TOKEN_FILE"

# Prepare nsupdate commands
NSUPDATE_CMD=$(mktemp)
cat > "$NSUPDATE_CMD" << EOF
server $DNS_SERVER
zone $DOMAIN.
update add $FULL_DOMAIN $TTL A 0.0.0.0
send
EOF

# Execute nsupdate
nsupdate -k "$KEY_FILE" "$NSUPDATE_CMD"
rm "$NSUPDATE_CMD"

echo "DNS record for $FULL_DOMAIN added successfully."

# Verify DNS record
echo "Verifying the DNS record..."
RESULT=$(dig +short @$DNS_SERVER $FULL_DOMAIN A)
if [[ $RESULT == "0.0.0.0" ]]; then
    echo "DNS record verification successful: $FULL_DOMAIN resolves to $RESULT"
else
    echo "Error: DNS record verification failed for $FULL_DOMAIN"
    exit 1
fi

# Verify token file
if [[ -f $TOKEN_FILE ]]; then
    echo "Token file verification successful: $TOKEN_FILE exists"
else
    echo "Error: Token file verification failed for $TOKEN_FILE"
    exit 1
fi

exit 0

