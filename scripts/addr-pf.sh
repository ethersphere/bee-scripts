#!/bin/bash

# Port-forward variant of addr.sh.
# Prints each node's ethereum address, reaching nodes via `kubectl port-forward`
# (lib/portforward.sh) instead of ingress: opens a local forward to one node at a
# time, GETs /addresses, then closes the forward and waits for the local port to free.
#
# Requires: kubectl, curl, jq, lsof.
# Usage: ./addr-pf.sh [NAMESPACE] [LOCAL_PORT] [API_PORT]
# Example: ./addr-pf.sh bee-base 11633 1633

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

for pod in "${pods[@]}"; do
    pf_aborted && { echo "Stopping early (cancellation requested)."; break; }

    # Opens the forward, GETs /addresses, then closes and waits for the port to free.
    json_data=$(pf_query "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" "/addresses")

    if [ $? -ne 0 ] || [ -z "$json_data" ]; then
        printf '%-20s | ERROR: could not reach /addresses\n' "$pod"
        continue
    fi

    eth=$(echo "$json_data" | jq -r '.ethereum // empty')
    printf '%-20s | %s\n' "$pod" "${eth:-<none>}"
done
