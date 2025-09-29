#!/bin/bash

# --- Endpoints ---
URL1_ENDPOINT="https://sepolia.example.org/"
URL2_ENDPOINT="https://sepolia.example.org/"
URL3_ENDPOINT="https://sepolia.example.org/"

COMMON_HEADERS="-H \"Content-Type: application/json\""
COMMON_DATA='{ "jsonrpc":"2.0", "method":"eth_maxPriorityFeePerGas", "params":[], "id":1 }'

# Create temporary files to store the output of each command
# mktemp creates a unique, secure temporary file
TMP_FILE1=$(mktemp)
TMP_FILE2=$(mktemp)
TMP_FILE3=$(mktemp)

# This is a safety net. It ensures the temporary files are removed when the script exits,
# even if it exits with an error.
trap 'rm -f "$TMP_FILE1" "$TMP_FILE2" "$TMP_FILE3"' EXIT

echo "Sending parallel POST requests..."
echo "------------------------------------"

# Start the POST requests in the background, redirecting their output (stdout) to the temp files.
# Pass the arguments directly to curl.
curl -s -X POST "$URL1_ENDPOINT" -H "Content-Type: application/json" -d "$COMMON_DATA" > "$TMP_FILE1" &
curl -s -X POST "$URL2_ENDPOINT" -H "Content-Type: application/json" -d "$COMMON_DATA" > "$TMP_FILE2" &
curl -s -X POST "$URL3_ENDPOINT" -H "Content-Type: application/json" -d "$COMMON_DATA" > "$TMP_FILE3" &

# Wait for both background jobs to complete writing to their files.
wait

# Now, read the contents of the completed files into variables.
# This happens in the main script, so the variables will be set correctly.
output1=$(cat "$TMP_FILE1")
output2=$(cat "$TMP_FILE2")
output3=$(cat "$TMP_FILE3")

echo
echo "All POST requests have completed."
echo
echo "--- Response from 1 ---"
echo "$output1"
echo "------------------------------------"
echo
echo "--- Response from 2 ---"
echo "$output2"
echo "------------------------------------"
echo
echo "--- Response from 3 ---"
echo "$output3"
echo "------------------------------------"