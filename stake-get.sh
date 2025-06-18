#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}

echo "Using namespace: $NAMESPACE"

counter=0

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=( $(kubectl get ingress -n "$NAMESPACE" | grep testnet.internal | awk '{print $3}') )

# Loop through each and curl the /stake endpoint
for url in "${list[@]}"; do
  echo "${url}/stake"
  curl -s "$url/stake"
  ((counter++))
done

# Print the total number of ingresses processed
echo "Total ingresses processed: $counter"
