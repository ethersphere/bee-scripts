#!/bin/bash

# Retrieves wallet balances from Bee nodes via `kubectl port-forward` instead of ingress.
# Unlike wallet-get.sh (which curls each ingress host directly), this opens a local
# port-forward to ONE node at a time, queries /wallet, then tears the forward down and
# blocks until the local port is released before moving on to the next node. The
# open/close-and-wait logic lives in lib/portforward.sh so other scripts can reuse it.
#
# Output per node: pod name | ethereum address | BZZ and native balances. The ethereum
# address comes from the /wallet response's walletAddress field (same value /addresses
# returns as .ethereum), so a single request per node suffices.
#
# Native token balances are gas amounts (often << 0.001), so they are shown with 8
# decimals; BZZ uses 4. Division is done with bc on the raw integers (not jq float math,
# which loses precision above 2^53) and printf rounds the result.
#
# Requires: kubectl, curl, jq, bc, lsof.
# Usage: ./wallet-get-pf.sh [NAMESPACE] [LOCAL_PORT] [API_PORT]
# Example: ./wallet-get-pf.sh bee-testnet 11633 1633

set -uo pipefail

source "$(dirname "$0")/lib/portforward.sh"

NAMESPACE=${1:-bee-testnet}
LOCAL_PORT=${2:-11633}   # local side of the forward; defaults high to avoid clobbering a local node
API_PORT=${3:-1633}      # Bee API port inside the pod

echo "Using namespace: $NAMESPACE  (local port $LOCAL_PORT -> node port $API_PORT)"

pods=($(pf_list_nodes "$NAMESPACE"))

if [[ ${#pods[@]} -eq 0 ]]; then
  echo "Error: no bee pods found in namespace '$NAMESPACE'"
  exit 1
fi

counter=0
for pod in "${pods[@]}"; do
  pf_aborted && { echo "Stopping early (cancellation requested)."; break; }

  # Opens the forward, GETs /wallet, then closes and waits for the port to free.
  json_data=$(pf_query "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" "/wallet")

  if [[ $? -ne 0 || -z "$json_data" ]]; then
    printf '%-20s | %-42s | ERROR: could not reach /wallet\n' "$pod" "-"
    ((counter++))
    continue
  fi

  eval "$(
    echo "$json_data" | jq -r '
      @sh "bzz_raw=\(.bzzBalance // "0")",
      @sh "native_raw=\(.nativeTokenBalance // "0")",
      @sh "wallet_addr=\(.walletAddress // "")"
    '
  )"

  # walletAddress is the node's ethereum address (same value /addresses returns as .ethereum),
  # so no extra request is needed.
  [[ -z "$wallet_addr" ]] && wallet_addr="<none>"

  # Divide the raw integers with bc (jq float math loses precision above 2^53), then
  # let printf round. 1 BZZ = 1e16 units; native token = 1e18 wei.
  bzz=$(echo "scale=20; $bzz_raw / 10000000000000000" | bc)
  native=$(echo "scale=20; $native_raw / 1000000000000000000" | bc)

  printf '%-20s | %-42s | BZZ: %9.4f, Native: %.8f\n' "$pod" "$wallet_addr" "$bzz" "$native"
  ((counter++))
done

echo "Total processed: $counter"
