#!/usr/bin/env bash
# youtube-split-tunnel.sh
# Updates a WireGuard export zip to route only Google/YouTube traffic through the tunnel.
# Usage: ./youtube-split-tunnel.sh [path-to-wireguard-export.zip]
# Default input: ~/Desktop/wireguard-export.zip

set -euo pipefail

ZIP_INPUT="${1:-$HOME/Desktop/wireguard-export.zip}"

if [[ ! -f "$ZIP_INPUT" ]]; then
  echo "Error: zip file not found: $ZIP_INPUT"
  echo "Usage: $0 [path-to-wireguard-export.zip]"
  exit 1
fi

# Work in a temp directory
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

echo "Extracting: $ZIP_INPUT"
unzip -q "$ZIP_INPUT" -d "$WORKDIR"

# Find all .conf files in the extracted zip
CONFIGS=($(find "$WORKDIR" -name "*.conf"))

if [[ ${#CONFIGS[@]} -eq 0 ]]; then
  echo "Error: no .conf files found inside the zip."
  exit 1
fi

echo "Found ${#CONFIGS[@]} config(s): ${CONFIGS[*]##*/}"
echo ""
echo "Fetching Google IP ranges..."

GOOGLE_IPS=$(curl -sf https://www.gstatic.com/ipranges/goog.json \
  | python3 -c "
import sys, json
data = json.load(sys.stdin)
prefixes = [p['ipv4Prefix'] for p in data['prefixes'] if 'ipv4Prefix' in p]
print(', '.join(sorted(prefixes)))
")

if [[ -z "$GOOGLE_IPS" ]]; then
  echo "Error: failed to fetch Google IP ranges. Check your internet connection."
  exit 1
fi

IP_COUNT=$(echo "$GOOGLE_IPS" | tr ',' '\n' | wc -l | tr -d ' ')
echo "Retrieved $IP_COUNT Google IPv4 CIDR blocks."
echo ""

# Update AllowedIPs in each config
for CONFIG in "${CONFIGS[@]}"; do
  TUNNEL_NAME=$(basename "$CONFIG" .conf)
  sed -i '' "s|^AllowedIPs = .*|AllowedIPs = ${GOOGLE_IPS}|" "$CONFIG"
  echo "Updated: $TUNNEL_NAME"
  echo "  AllowedIPs = $(grep '^AllowedIPs' "$CONFIG" | head -c 100)..."
  echo ""
done

# Repackage into a new zip on the Desktop
OUTPUT_ZIP="$HOME/Desktop/wireguard-youtube-split.zip"
(cd "$WORKDIR" && zip -qr "$OUTPUT_ZIP" .)

echo "Output saved to: $OUTPUT_ZIP"
echo ""
echo "Next steps (macOS WireGuard app):"
echo "  1. Delete the existing tunnel in the app"
echo "  2. Click '+' → Import tunnel(s) from file → select wireguard-youtube-split.zip"
