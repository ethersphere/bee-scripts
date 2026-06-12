#!/bin/bash

# Port-forward variant of chequebook-balance-get.sh.
# Instead of curling each ingress host, it opens a `kubectl port-forward` to one node at
# a time (via lib/portforward.sh), reads /chequebook/balance, then closes the forward and
# waits for the local port to free before the next node. Flags nodes below the minimum
# chequebook threshold (11 BZZ).
#
# Requires: kubectl, curl, jq, bc, lsof.
# Usage: ./chequebook-balance-get-pf.sh [NAMESPACE] [LOCAL_PORT] [API_PORT]
# Example: ./chequebook-balance-get-pf.sh bee-light-testnet 11633 1633

set -uo pipefail

source "$(dirname "$0")/lib/portforward.sh"

NAMESPACE=${1:-bee-testnet}
LOCAL_PORT=${2:-11633}   # local side of the forward; defaults high to avoid clobbering a local node
API_PORT=${3:-1633}      # Bee API port inside the pod

# 11 BZZ expressed in token units (1 BZZ = 1e16 token units for display, 1.1e17 raw)
MIN_BALANCE=110000000000000000

echo "Using namespace: $NAMESPACE  (local port $LOCAL_PORT -> node port $API_PORT)"
echo "Minimum required balance: 11.00 BZZ (${MIN_BALANCE} token units)"
echo ""

pods=($(pf_list_nodes "$NAMESPACE"))

if [ ${#pods[@]} -eq 0 ]; then
    echo "Error: no bee pods found in namespace '$NAMESPACE'"
    exit 1
fi

counter=0
below_min=0

for pod in "${pods[@]}"; do
    # Opens the forward, GETs /chequebook/balance, then closes and waits for the port to free.
    json_data=$(pf_query "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" "/chequebook/balance")

    if [ $? -ne 0 ] || [ -z "$json_data" ]; then
        printf '%-20s | ERROR: could not reach /chequebook/balance\n' "$pod"
        ((counter++))
        continue
    fi

    eval "$(
        echo "$json_data" | jq -r '
            @sh "total_raw=\(.totalBalance // "0")",
            @sh "avail_raw=\(.availableBalance // "0")"
        '
    )"

    total_bzz=$(echo "scale=2; $total_raw / 10000000000000000" | bc)
    avail_bzz=$(echo "scale=2; $avail_raw / 10000000000000000" | bc)

    flag=""
    if [ "$total_raw" -lt "$MIN_BALANCE" ] 2>/dev/null; then
        flag=" *** BELOW MIN ***"
        ((below_min++))
    fi

    printf '%-20s | total: %8.2f BZZ  available: %8.2f BZZ%s\n' \
        "$pod" "$total_bzz" "$avail_bzz" "$flag"

    ((counter++))
done

echo ""
echo "Total processed: $counter  |  Below minimum (11 BZZ): $below_min"
