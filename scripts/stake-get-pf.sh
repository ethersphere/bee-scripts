#!/bin/bash

# Port-forward variant of stake-get.sh.
# Reports each node's staked amount, reaching nodes via `kubectl port-forward`
# (lib/portforward.sh) instead of ingress: opens a local forward to one node at a time,
# GETs /stake, then closes the forward and waits for the local port to free.
#
# /stake returns {"stakedAmount":"<plur>"} where 1 BZZ = 1e16 plur; division is done
# with bc on the raw integer (jq float math loses precision above 2^53).
#
# Requires: kubectl, curl, jq, bc, lsof.
# Usage: ./stake-get-pf.sh [NAMESPACE] [LOCAL_PORT] [API_PORT]
# Example: ./stake-get-pf.sh bee-base 11633 1633

set -uo pipefail

source "$(dirname "$0")/lib/portforward.sh"

NAMESPACE=${1:-bee-testnet}
LOCAL_PORT=${2:-11633}   # local side of the forward; defaults high to avoid clobbering a local node
API_PORT=${3:-1633}      # Bee API port inside the pod

echo "Using namespace: $NAMESPACE  (local port $LOCAL_PORT -> node port $API_PORT)"

pods=($(pf_list_nodes "$NAMESPACE"))

if [ ${#pods[@]} -eq 0 ]; then
    echo "Error: no bee pods found in namespace '$NAMESPACE'"
    exit 1
fi

counter=0
staked_nodes=0

for pod in "${pods[@]}"; do
    pf_aborted && { echo ""; echo "Stopping early (cancellation requested)."; break; }

    # Opens the forward, GETs /stake, then closes and waits for the port to free.
    json_data=$(pf_query "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" "/stake")

    if [ $? -ne 0 ] || [ -z "$json_data" ]; then
        printf '%-20s | ERROR: could not reach /stake\n' "$pod"
        ((counter++))
        continue
    fi

    staked_raw=$(echo "$json_data" | jq -r '.stakedAmount // "0"')
    if ! [[ "$staked_raw" =~ ^[0-9]+$ ]]; then
        printf '%-20s | ERROR: could not parse stakedAmount\n' "$pod"
        ((counter++))
        continue
    fi

    staked_bzz=$(echo "scale=20; $staked_raw / 10000000000000000" | bc)
    [ "$staked_raw" != "0" ] && ((staked_nodes++))

    printf '%-20s | staked: %9.4f BZZ\n' "$pod" "$staked_bzz"
    ((counter++))
done

echo ""
echo "Total processed: $counter  |  Staked nodes: $staked_nodes"
