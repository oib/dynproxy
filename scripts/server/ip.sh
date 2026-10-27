#!/bin/zsh
# Script Version: 03
# Description: Display client's IPv4 or IPv6 address

echo "Content-type: text/plain"
echo ""

# Simply echo the REMOTE_ADDR without extra checks
echo "$REMOTE_ADDR"
