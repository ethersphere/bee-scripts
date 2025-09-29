#!/bin/bash

# --- Endpoints ---
URL1="http://bee-3-1.bee-testnet.testnet.internal/stamps/1440000000/20?label=test-label"
URL2="http://bee-3-1.lightnet.testnet.internal/stamps/1440000000/20?label=test-label"
URL3="http://localhost:1633/stamps/1440000000/20?label=test-label"

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
curl -s -X POST "$URL1" > "$TMP_FILE1" &
curl -s -X POST "$URL2" > "$TMP_FILE2" &
curl -s -X POST "$URL3" > "$TMP_FILE3" &

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
echo "--- Response from bee-testnet ---"
echo "$output1"
echo "------------------------------------"
echo
echo "--- Response from bee-lightnet ---"
echo "$output2"
echo "------------------------------------"
echo
echo "--- Response from localhost ---"
echo "$output3"
echo "------------------------------------"
echo
