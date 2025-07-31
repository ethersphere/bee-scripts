#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}

echo "Using namespace: $NAMESPACE"

counter=0

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=( $(kubectl get ingress -n "$NAMESPACE" | grep testnet.internal | awk '{print $3}') )

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
