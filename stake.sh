#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}

echo "Using namespace: $NAMESPACE"

counter=0
stake_amount=100000000000000000

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=( $(kubectl get ingress -n "$NAMESPACE" | grep testnet.internal | awk '{print $3}') )

# Loop through each and send POST to /stake/<amount>
for url in "${list[@]}"; do
  echo "POST ${url}/stake/${stake_amount}"
  response=$(curl -s -XPOST "${url}/stake/${stake_amount}")
  echo "Response from $url: $response"

  # Check if response contains "insufficient stake amount"
  if echo "$response" | grep -q '"code":400' && echo "$response" | grep -q 'insufficient stake amount'; then
    doubled_amount=$((stake_amount * 2))
    echo "Retrying ${url} with doubled amount: $doubled_amount"
    retry_response=$(curl -s -XPOST "${url}/stake/${doubled_amount}")
    echo "Retry response from $url: $retry_response"
  fi

  ((counter++))
done

# Print the total number of ingresses processed
echo "Total ingresses processed: $counter"
