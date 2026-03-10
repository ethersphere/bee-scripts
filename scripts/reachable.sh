#!/bin/bash

# This script checks if Bee nodes are reachable by inspecting the 'isReachable' field from the /status endpoint.
# It requires 'kubectl', 'curl', and 'jq' to be installed on the system.
# Usage: ./reachable.sh [NAMESPACE] [DOMAIN]
# Example: ./reachable.sh bee-testnet testnet.internal

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"

# Get list of ingress hosts/IPs matching the domain in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

counter=0
reachable_count=0
unreachable_count=0

echo "Checking node reachability from /status endpoint..."
echo "=========================================================="

for url in "${list[@]}"; do
  echo "Processing: $url"

  # Fetch the JSON data from the status endpoint
  json_data=$(curl -s "${url}/status")

  # Check if the request was successful
  if [ $? -ne 0 ] || [ -z "$json_data" ]; then
    echo "  ❌ Failed to fetch data from $url"
    ((counter++))
    ((unreachable_count++))
    continue
  fi

  # Extract the isReachable field (use if/then to avoid // treating false as missing)
  reachability=$(echo "$json_data" | jq -r 'if .isReachable == null then "N/A" else .isReachable end')

  if [ "$reachability" = "N/A" ]; then
    echo "  ⚠️  No isReachable field found in response from $url"
  elif [ "$reachability" = "true" ]; then
    echo "  ✅ Reachable"
    ((reachable_count++))
  else
    echo "  ❌ Not reachable"
    ((unreachable_count++))
  fi

  ((counter++))
done

echo "=========================================================="
echo "📈 SUMMARY:"
echo "Total endpoints processed: $counter"
echo "Reachable:                 $reachable_count"
echo "Not reachable:             $unreachable_count"
echo ""
echo "✅ Analysis complete!"
