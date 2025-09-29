#!/bin/bash

# This script deletes stake information from multiple Bee nodes in a specified Kubernetes namespace.
# It requires 'kubectl' and 'curl' to be installed on the system. 
# Usage: ./stake-del.sh [NAMESPACE] [DOMAIN]
# Example: ./stake-del.sh bee-testnet testnet.internal

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

counter=0

# Loop through each and send DELETE to the /stake endpoint in background
for url in "${list[@]}"; do
  echo "DELETE ${url}/stake"
  curl -XDELETE -s "${url}/stake" &
  ((counter++))
done

# Wait for all background curls to finish
wait

# Print the total number of ingresses processed
echo "Total ingresses processed: $counter"
