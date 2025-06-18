#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}

echo "Using namespace: $NAMESPACE"

total_nodes_processed=0
total_pending_transactions=0

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
# We're no longer pre-filtering here, but will do so inside the loop.
list=( $(kubectl get ingress -n "$NAMESPACE" | grep testnet.internal | awk '{print $3}') )

# Define the regex pattern for valid node URLs (e.g., contains bee-X-Y)
# Note: No ^ or $ anchors as we're looking for a containment.
# The `.` for literal dot doesn't need to be escaped in basic regex within [[ ]].
# However, for consistency and robustness in case it's used elsewhere, escaping is good practice.
NODE_URL_CONTAINS_PATTERN="bee-[0-9]+-[0-9]+"

# Loop through each and curl the /transactions endpoint
for url in "${list[@]}"; do
  # Filter out load balancers: Only process URLs that *contain* the node pattern
  if [[ "$url" =~ $NODE_URL_CONTAINS_PATTERN ]]; then
    echo "--- Processing node: ${url} ---"
    response=$(curl -s "${url}/transactions")

    # Check if curl was successful and response is not empty
    if [ -n "$response" ]; then
      # Parse the JSON response
      # Count pending transactions
      pending_count=$(echo "$response" | jq '.pendingTransactions | length')

      if [ -n "$pending_count" ]; then
        echo "  Number of pending transactions: $pending_count"
        total_pending_transactions=$((total_pending_transactions + pending_count))

        # Extract transactionHash and created for each pending transaction
        transaction_details=$(echo "$response" | jq -c '.pendingTransactions[] | {transactionHash: .transactionHash, created: .created}')

        if [ -n "$transaction_details" ]; then
          echo "  Pending Transaction Details:"
          echo "$transaction_details" | while IFS= read -r line; do
            echo "    - $line"
          done
        else
          echo "  No detailed transaction information found."
        fi
      else
        echo "  Could not parse pending transactions count from response."
      fi
    else
      echo "  Failed to get a response from ${url}/transactions"
    fi
    ((total_nodes_processed++))
  fi
done

# Print the total number of ingresses processed and total pending transactions
echo "--- Summary ---"
echo "Total nodes processed (individual nodes): $total_nodes_processed"
echo "Total pending transactions across all individual nodes: $total_pending_transactions"