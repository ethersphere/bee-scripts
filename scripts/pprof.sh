#!/bin/bash

# This script retrieves pprof profiles from a Bee node debug endpoint.
# It requires 'curl' to be installed on the system.
# Usage: ./pprof.sh <HOST>
# Example: ./pprof.sh bee-1-0.bee-testnet.testnet.internal

# Check if host is provided as the first argument
if [ -z "$1" ]; then
  echo "Error: Please provide a host as the first argument."
  echo "Example: ./pprof.sh bee-1-0.bee-testnet.testnet.internal"
  exit 1
fi

HOST="$1"

# Convert host to debug endpoint format
# e.g., bee-1-0.bee-testnet.testnet.internal -> bee-1-0-debug.bee-testnet.testnet.internal
DEBUG_HOST=$(echo "$HOST" | sed 's/^\([^.]*\)\./\1-debug./')

echo "Fetching pprof profile from: $DEBUG_HOST"
echo "Using host: $HOST"
echo "Debug endpoint: $DEBUG_HOST"

# Generate timestamp for filename
TIMESTAMP=$(date +%T-%m-%d-%Y)
OUTPUT_FILE="tmp-pprof-${HOST//\./-}-${TIMESTAMP}"

# Fetch pprof profile
echo "Downloading pprof profile..."
curl -s "http://${DEBUG_HOST}/debug/pprof/profile" -o "$OUTPUT_FILE"

# Check if curl was successful
if [ $? -ne 0 ] || [ ! -s "$OUTPUT_FILE" ]; then
  echo "❌ Failed to fetch pprof profile from ${DEBUG_HOST}/debug/pprof/profile"
  rm -f "$OUTPUT_FILE"
  exit 1
fi

echo "✅ Successfully downloaded pprof profile: $OUTPUT_FILE"

# Create tar.gz archive
ARCHIVE_NAME="pprof-${HOST//\./-}-${TIMESTAMP}.tar.gz"
echo "Creating archive: $ARCHIVE_NAME"
tar -czf "$ARCHIVE_NAME" "$OUTPUT_FILE"

if [ $? -eq 0 ]; then
  echo "✅ Archive created successfully: $ARCHIVE_NAME"
  rm -f "$OUTPUT_FILE"
  echo "✅ Cleaned up temporary file"
else
  echo "❌ Failed to create archive"
  exit 1
fi

echo ""
echo "✅ Analysis complete! Archive saved as: $ARCHIVE_NAME"
