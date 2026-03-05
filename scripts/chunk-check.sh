#!/bin/bash

# This script checks if a specific chunk exists on multiple Bee nodes in a specified Kubernetes namespace.
# It requires 'kubectl', 'curl', and 'jq' to be installed on the system.
# Usage: ./chunk-check.sh [NAMESPACE] [DOMAIN] [CHUNK_ADDRESS]
# Example: ./chunk-check.sh bee-testnet testnet.internal abc123def456...

NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}
CHUNK_ADDRESS=${3}

if [ -z "$CHUNK_ADDRESS" ]; then
  echo "Error: CHUNK_ADDRESS is required"
  echo "Usage: $0 [NAMESPACE] [DOMAIN] [CHUNK_ADDRESS]"
  exit 1
fi

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"
echo "Checking for chunk: $CHUNK_ADDRESS"

list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

echo "Checking chunk existence across all ingress endpoints..."
echo "=========================================================="

for url in "${list[@]}"; do
  (
    http_status=$(curl -s -o /dev/null -w "%{http_code}" -I --max-time 10 "${url}/chunks/${CHUNK_ADDRESS}")
    if [ "$http_status" = "200" ]; then
      echo "FOUND      $url"
      echo '{"node":"'"$url"'","status":"found","http_code":"'"$http_status"'"}' > "$TMPDIR/$url"
    elif [ "$http_status" = "404" ]; then
      echo "NOT FOUND  $url"
      echo '{"node":"'"$url"'","status":"not_found","http_code":"'"$http_status"'"}' > "$TMPDIR/$url"
    else
      echo "ERROR $http_status  $url"
      echo '{"node":"'"$url"'","status":"error","http_code":"'"$http_status"'"}' > "$TMPDIR/$url"
    fi
  ) &
done

wait

echo "=========================================================="

nodes=$(cat "$TMPDIR"/* 2>/dev/null | jq -s '.')
total=$(echo "$nodes" | jq 'length')
found=$(echo "$nodes" | jq '[.[] | select(.status=="found")] | length')
not_found=$(echo "$nodes" | jq '[.[] | select(.status=="not_found")] | length')
errors=$(echo "$nodes" | jq '[.[] | select(.status=="error")] | length')

jq -n \
  --arg chunk "$CHUNK_ADDRESS" \
  --argjson total "$total" \
  --argjson found "$found" \
  --argjson not_found "$not_found" \
  --argjson errors "$errors" \
  --argjson nodes "$nodes" \
  '{
    chunk_address: $chunk,
    summary: { total: $total, found: $found, not_found: $not_found, errors: $errors },
    nodes: $nodes
  }'
