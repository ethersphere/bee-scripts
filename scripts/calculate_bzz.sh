#!/bin/bash

# This script calculates the amount of BZZ required to fund a postage stamp
# for a specified duration and depth using data fetched from a Bee node's
# chainstate endpoint.
# It retrieves the current postage stamp price from the Bee node's ingress
# and performs the necessary calculations.
# Requirements:
# - kubectl
# - curl
# - jq
# - bc  
# Usage: ./calculate_bzz.sh [namespace] [hours] [depth] [blocktime]
# Example: ./calculate_bzz.sh bee-testnet 24 22 12

# Default values
DEFAULT_NAMESPACE="bee-testnet"
DEFAULT_HOURS=24
DEFAULT_DEPTH=22
DEFAULT_BLOCKTIME=12

# Use passed arguments or defaults
NAMESPACE=${1:-$DEFAULT_NAMESPACE}
HOURS=${2:-$DEFAULT_HOURS}
DEPTH=${3:-$DEFAULT_DEPTH}
BLOCKTIME=${4:-$DEFAULT_BLOCKTIME}

echo "📝 Using Configuration:"
echo "   Namespace:  $NAMESPACE"
echo "   Hours:      $HOURS"
echo "   Depth:      $DEPTH"
echo "   Block Time: $BLOCKTIME seconds"
echo "---"

# --- Step 1: Find the first ingress URL ---
echo "🔎 Finding the first ingress in namespace '$NAMESPACE'..."
URL=$(kubectl get ingress -n "$NAMESPACE" --no-headers -o custom-columns=":spec.rules[0].host" | grep 'testnet.internal' | head -n 1)

if [ -z "$URL" ]; then
  echo "❌ Error: Could not find any ingress matching 'testnet.internal' in namespace '$NAMESPACE'."
  exit 1
fi
echo "✅ Found ingress: $URL"

# --- Step 2: Fetch chainstate data ---
echo "🌐 Fetching chainstate data from ${URL}/chainstate..."
JSON_DATA=$(curl -s "${URL}/chainstate")

if [ -z "$JSON_DATA" ] || ! echo "$JSON_DATA" | jq . > /dev/null 2>&1; then
  echo "❌ Error: Failed to fetch valid JSON data from ${URL}/chainstate."
  exit 1
fi

CURRENT_PRICE=$(echo "$JSON_DATA" | jq -r '.currentPrice')

if [ "$CURRENT_PRICE" == "null" ] || [ -z "$CURRENT_PRICE" ]; then
    echo "❌ Error: Could not parse 'currentPrice' from the JSON response."
    echo "   Received data: $JSON_DATA"
    exit 1
fi
echo "🪙 Current postage stamp price (per block): $CURRENT_PRICE"
echo "---"

# --- Step 3: Calculate required BZZ using bc for precision ---
echo "🧮 Calculating required BZZ amount..."

# bc is used for floating-point arithmetic since bash only handles integers.
# 'scale=4' sets the precision to 4 decimal places.
# '2^$DEPTH' is the 'bc' equivalent of '1<<$DEPTH'.
# '10^16' is used for '1e16'.
CALCULATION_RESULT=$(bc -l <<EOF
    scale=4
    amount = (${HOURS} * 60 * 60 / ${BLOCKTIME}) * ${CURRENT_PRICE}
    bzz_price = (amount * (2^${DEPTH})) / (10^16)
    print amount, " ", bzz_price
EOF
)

# Parse the results
AMOUNT_PLUR=$(echo "$CALCULATION_RESULT" | awk '{print $1}')
BZZ_REQUIRED=$(echo "$CALCULATION_RESULT" | awk '{print $2}')

# --- Step 4: Display the result ---
printf "\n✨ To fund a postage stamp for %d hours at depth %d:\n" "$HOURS" "$DEPTH"
printf "   Amount in PLUR: %.0f\n" "$AMOUNT_PLUR"
printf "   Amount in BZZ:  %.4f\n" "$BZZ_REQUIRED"
