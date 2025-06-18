#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}

echo "Using namespace: $NAMESPACE"

counter=0

list=( $(kubectl get ingress -n "$NAMESPACE" | grep testnet.internal | awk '{print $3}') )

for url in "${list[@]}"; do
  # Fetch the JSON data from the curl command
  json_data=$(curl -s "${url}/wallet")

  # Use your excellent eval technique to safely pull values into shell variables
  eval "$( \
    echo "$json_data" | jq -r '
      @sh "bzz_val=\(.bzzBalance | tonumber / 1e16)",
      @sh "native_val=\(.nativeTokenBalance | tonumber / 1e18)"
    ' \
  )"

  # Now, use the shell's own printf with the newly created variables
  printf '%s | BZZ: %.2f, Native: %.2f\n' "$url" "$bzz_val" "$native_val"

  ((counter++))
done

echo "Total processed: $counter"
