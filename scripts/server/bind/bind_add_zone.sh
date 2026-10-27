#!/bin/zsh
# Version 01.0
# Script to add a new zone to /etc/bind/named.conf.local on ns1.dynproxy.net
# Script Name: bind_add_zone.sh

# Variables
NAMED_CONF="/etc/bind/named.conf.local"
ZONES_DIR="/etc/bind/zones"

# Check if a domain name argument is provided
if [ -z "$1" ]; then
	echo "Usage: $0 <domain.tld>"
	exit 1
fi

DOMAIN=$1
ZONE_FILE="$ZONES_DIR/db.$DOMAIN"

# Check if the zone file already exists
if [ -f "$ZONE_FILE" ]; then
	echo "Zone file $ZONE_FILE already exists. Aborting."
	exit 2
fi

# Append zone configuration to named.conf.local
echo "Adding zone configuration for $DOMAIN to $NAMED_CONF"
cat <<EOF >> $NAMED_CONF
zone "$DOMAIN" {
	type master;
	file "$ZONE_FILE";
	allow-transfer { 116.202.112.180; 95.216.198.140; key "ns3-key"; };
	also-notify { 116.202.112.180; 95.216.198.140; };
};
EOF

# Create the zone file with a basic template
echo "Creating zone file $ZONE_FILE"
cat <<EOF > $ZONE_FILE
\$ORIGIN $DOMAIN.
\$TTL 604800	; 1 week
@       IN SOA	ns1.dynproxy.net. dns.bubuit.net. (
			$(date +%Y%m%d)01 ; Serial
			604800		   ; Refresh (1 week)
			86400		   ; Retry (1 day)
			2419200		   ; Expire (4 weeks)
			604800		   ; Minimum (1 week)
		)
		IN NS	ns1.dynproxy.net.
		IN NS	ns2.dynproxy.net.
		IN NS	ns3.dynproxy.net.

		IN A	116.202.112.180
		IN MX	10 mail
		IN TXT	"v=spf1 mx -all"

mail	IN A	116.202.112.180
EOF

# Set permissions
echo "Setting permissions for $ZONE_FILE"
chown bind:bind "$ZONE_FILE"
chmod 640 "$ZONE_FILE"

# Reload BIND configuration
echo "Reloading BIND configuration"
rndc reload

# Success message
echo "Zone for $DOMAIN has been added successfully"

