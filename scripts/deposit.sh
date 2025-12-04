#!/bin/bash

# This script deposits to the chequebook endpoint for all Bee nodes in a specified Kubernetes namespace.
# It requires 'kubectl' and 'curl' to be installed on the system.
# Usage: ./deposit.sh [NAMESPACE] [AMOUNT] [DOMAIN]
# Example: ./deposit.sh bee-testnet 117000000 testnet.internal

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
AMOUNT=$2
DOMAIN=${3:-testnet.internal}

# Check if amount is provided
if [ -z "$AMOUNT" ]; then
  echo "Error: Please provide an amount as the second argument."
  echo "Usage: ./deposit.sh [NAMESPACE] [AMOUNT] [DOMAIN]"
  echo "Example: ./deposit.sh bee-testnet 117000000 testnet.internal"
  exit 1
fi

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"
echo "Deposit amount: $AMOUNT"

# Get list of ingress hosts/IPs matching the domain in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

if [ ${#list[@]} -eq 0 ]; then
  echo "⚠️  No ingresses found in namespace: $NAMESPACE matching domain: $DOMAIN"
  exit 1
fi

counter=0
success_count=0
fail_count=0

# Loop through each node and send POST to /chequebook/deposit?amount=<amount>
for url in "${list[@]}"; do
  # Ensure URL has http:// prefix
  if [[ ! "$url" =~ ^https?:// ]]; then
    url="http://${url}"
  fi
  
  endpoint="${url}/chequebook/deposit?amount=${AMOUNT}"
  echo "POST ${endpoint}"
  
  response=$(curl -s -w "\n%{http_code}" -X POST "${endpoint}")
  http_code=$(echo "$response" | tail -n1)
  response_body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "✅ Success (HTTP $http_code) from $url: $response_body"
    ((success_count++))
  else
    echo "❌ Failed (HTTP $http_code) from $url: $response_body"
    ((fail_count++))
  fi
  
  ((counter++))
done

# Print summary
echo ""
echo "Total nodes processed: $counter"
echo "✅ Successful: $success_count"
echo "❌ Failed: $fail_count"
