#!/bin/bash

# This script retrieves the current base fee per gas from an Ethereum node using its RPC endpoint.
# It requires 'curl' and 'jq' to be installed on the system.
# Usage: ./get_base_fee.sh <RPC_URL>
# Example: ./get_base_fee.sh https://mainnet.infura.io/v3/YOUR_API_KEY

# Check if RPC URL is provided as the first argument
if [ -z "$1" ]; then
  echo "Error: Please provide an RPC endpoint URL as the first argument."
  echo "Example: ./get_base_fee.sh https://mainnet.infura.io/v3/YOUR_API_KEY"
  exit 1
fi

# Ethereum node RPC endpoint (from first argument)
RPC_URL="$1"

# Send curl request to get the latest block's baseFeePerGas
response=$(curl -s -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", false],"id":1}' \
  "$RPC_URL")

# Check if the response contains an error
if echo "$response" | jq -e '.error' >/dev/null; then
  echo "Error: $(echo "$response" | jq -r '.error.message')"
  exit 1
fi

# Extract baseFeePerGas (hexadecimal)
hex_fee=$(echo "$response" | jq -r '.result.baseFeePerGas')

# Check if baseFeePerGas is present
if [ -z "$hex_fee" ] || [ "$hex_fee" == "null" ]; then
  echo "Error: Could not retrieve baseFeePerGas. Check if the node supports EIP-1559."
  exit 1
fi

# Convert hex to decimal (wei)
decimal_fee=$((16#${hex_fee#0x}))

# Convert wei to Gwei (1 Gwei = 1,000,000,000 wei)
gwei_fee=$(echo "scale=9; $decimal_fee / 1000000000" | bc)

# Output the result
echo "Base Fee: $decimal_fee wei"
echo "Base Fee: $gwei_fee Gwei"
