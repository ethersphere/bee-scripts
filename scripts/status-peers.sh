#!/bin/bash

# This script retrieves connected peers count from multiple Bee nodes in a specified Kubernetes namespace.
# It requires 'kubectl', 'curl', and 'jq' to be installed on the system.
# Usage: ./status-peers.sh [NAMESPACE] [DOMAIN]
# Example: ./status-peers.sh bee-testnet testnet.internal

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"

# Get list of ingress hosts/IPs matching the domain in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

counter=0
successful_requests=0

echo "Fetching connected peers count from all ingress endpoints..."
echo "=========================================================="

for url in "${list[@]}"; do
  echo "Processing: $url"
  
  # Fetch the JSON data from the curl command
  json_data=$(curl -s "${url}/status")
  
  # Check if the request was successful
  if [ $? -ne 0 ] || [ -z "$json_data" ]; then
    echo "  ❌ Failed to fetch data from $url"
    continue
  fi
  
  # Extract connectedPeers count
  connected_peers=$(echo "$json_data" | jq -r '.connectedPeers // "N/A"')
  
  if [ "$connected_peers" = "N/A" ] || [ "$connected_peers" = "null" ]; then
    echo "  ⚠️  No connectedPeers field found in response from $url"
    continue
  fi
  
  # Display the count if it's a number
  if [[ "$connected_peers" =~ ^[0-9]+$ ]]; then
    echo "  👥 Connected peers: $connected_peers"
    ((successful_requests++))
  else
    echo "  ⚠️  Invalid connectedPeers value: $connected_peers"
  fi
  
  ((counter++))
done

echo "=========================================================="
echo "📈 SUMMARY:"
echo "Total endpoints processed: $counter"
echo "Successful requests: $successful_requests"

echo ""
echo "✅ Analysis complete!"
