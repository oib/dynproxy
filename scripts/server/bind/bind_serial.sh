#!/bin/bash
# Script Version: 05
# Description: Updates the serial number in a BIND zone file based on the given domain. If today's date is already used, increments the last two digits.

ZONE_NAME="$1"
ZONE_FILE="/etc/bind/zones/db.$ZONE_NAME"

if [ -z "$ZONE_NAME" ] || [ ! -f "$ZONE_FILE" ]; then
  echo "Usage: $0 domain.name (e.g., dynproxy.net)"
  exit 1
fi

# Extract current serial number from the zone file
CURRENT_SERIAL=$(grep -E '^[[:space:]]*[0-9]{10}' "$ZONE_FILE" | head -1 | awk '{print $1}')
if [ -z "$CURRENT_SERIAL" ]; then
  echo "Error: Could not find a valid serial in $ZONE_FILE"
  exit 2
fi

# Get date part and counter part
DATE_PART=$(date +%Y%m%d)
SERIAL_DATE=${CURRENT_SERIAL:0:8}
SERIAL_COUNT=${CURRENT_SERIAL:8:2}

if [ "$SERIAL_DATE" == "$DATE_PART" ]; then
  NEW_COUNT=$(printf "%02d" $((10#$SERIAL_COUNT + 1)))
else
  NEW_COUNT="01"
fi

NEW_SERIAL="${DATE_PART}${NEW_COUNT}"

# Replace the serial in the file
sed -i "s/$CURRENT_SERIAL/$NEW_SERIAL/" "$ZONE_FILE"

echo "Serial updated in $ZONE_FILE: $CURRENT_SERIAL -> $NEW_SERIAL"

# Run named-checkzone for validation
if named-checkzone "$ZONE_NAME" "$ZONE_FILE"; then
  echo "Zone validation successful. Reloading zone..."
  rndc reload "$ZONE_NAME"
  rndc notify "$ZONE_NAME"
else
  echo "Zone validation failed. Not reloading."
  exit 3
fi

