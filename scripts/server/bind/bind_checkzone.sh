#!/bin/zsh
# Version 02.9

# Variables
NAMED_CONF_LOCAL="/etc/bind/named.conf.local"
CHECKZONE_CMD="named-checkzone"

# Function to parse zones and file paths
parse_zones() {
    awk '/zone/ {gsub(/[\";]/, ""); zone=$2} /file/ {gsub(/[\";]/, ""); file=$2; print file}' "$NAMED_CONF_LOCAL"
}

# Main function
main() {
    echo "Parsing $NAMED_CONF_LOCAL for zone files"

    parse_zones | while read -r ZONE_FILE; do
        if [ -z "$ZONE_FILE" ]; then
            echo "No file specified for zone"
            continue
        fi

        if [ -f "$ZONE_FILE" ]; then
            # Extract the zone name from the file path after 'db.'
            ZONE="$(basename "$ZONE_FILE" | sed 's/^db\.//')"

            echo "\n=== Checking Zone: $ZONE ==="
            echo "Zone file: $ZONE_FILE"

            # Directly execute the check
            $CHECKZONE_CMD "$ZONE" "$ZONE_FILE"
            STATUS=$?

            if [ $STATUS -ne 0 ]; then
                echo "Error: Zone $ZONE has issues"
            else
                echo "Success: Zone $ZONE is valid"
            fi
        else
            echo "Error: Zone file $ZONE_FILE does not exist"
        fi
    done
}

main

