#!/bin/bash
# Script: chequebook-deposit-pf.sh
# Description: Port-forward variant of chequebook-deposit.sh. POSTs /chequebook/deposit for
#   each node, reaching it via `kubectl port-forward` (lib/portforward.sh) rather than ingress.
#   For each node it opens ONE forward, optionally reads the current balance (--topup-to),
#   POSTs the deposit, then closes the forward and waits for the local port to free.
#
# Requires: kubectl, curl, jq, lsof.
# Usage: ./chequebook-deposit-pf.sh <namespace> <amount> [--topup-to]
#   --topup-to: treat <amount> as a target total balance; fetch each node's current
#               balance and deposit only the difference needed to reach that target.
#   LOCAL_PORT / API_PORT may be overridden via environment (defaults 11633 / 1633).
#   For parity with the non-pf sibling, a legacy <domain> arg between <namespace> and
#   <amount> is accepted and ignored (nodes are discovered by label, not ingress).
# Example: ./chequebook-deposit-pf.sh bee-testnet 117000000
# Example: LOCAL_PORT=12000 ./chequebook-deposit-pf.sh bee-testnet 117000000 --topup-to

set -uo pipefail

source "$(dirname "$0")/lib/portforward.sh"

NAMESPACE=${1:-}

# This variant takes no domain (nodes are discovered by label), but the non-pf sibling
# uses "<namespace> <domain> <amount>". Accept that legacy order too: if the 2nd arg
# isn't the amount but the 3rd is, treat the 2nd as an (ignored) domain.
if [[ "${2:-}" =~ ^[0-9]+$ ]]; then
    AMOUNT=${2:-}
    FLAG=${3:-}
elif [[ -n "${2:-}" && "${3:-}" =~ ^[0-9]+$ ]]; then
    echo "Note: ignoring '$2' — this variant takes no domain (nodes found by label)." >&2
    AMOUNT=${3}
    FLAG=${4:-}
else
    AMOUNT=${2:-}      # empty or invalid; caught by validation below
    FLAG=${3:-}
fi

TOPUP_TO=false
[ "$FLAG" = "--topup-to" ] && TOPUP_TO=true

LOCAL_PORT=${LOCAL_PORT:-11633}   # local side of the forward; defaults high to avoid clobbering a local node
API_PORT=${API_PORT:-1633}        # Bee API port inside the pod

if [ -z "$NAMESPACE" ] || [ -z "$AMOUNT" ]; then
    echo "Usage: $0 <namespace> <amount> [--topup-to]"
    echo "  amount      deposit amount, or target balance when --topup-to is set"
    echo "  --topup-to  fetch current balance per node and deposit only the difference"
    echo "  LOCAL_PORT / API_PORT overridable via env (defaults 11633 / 1633)"
    echo "  (a legacy <domain> arg between namespace and amount is accepted and ignored)"
    echo "Example: $0 bee-testnet 117000000"
    echo "Example: $0 bee-testnet 117000000 --topup-to"
    exit 1
fi

# Validate amount is a number
if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: amount must be a positive integer"
    exit 1
fi

pods=($(pf_list_nodes "$NAMESPACE"))

if [ ${#pods[@]} -eq 0 ]; then
    echo "Error: no bee pods found in namespace '$NAMESPACE'"
    exit 1
fi

echo "Found ${#pods[@]} bee nodes in namespace '$NAMESPACE'  (local port $LOCAL_PORT -> node port $API_PORT)"
if [ "$TOPUP_TO" = true ]; then
    echo "Mode: topup-to (target balance: $AMOUNT)"
else
    echo "Executing deposit requests with amount: $AMOUNT"
fi
echo ""

# Results accumulate here; populated by process_node (a global, NOT run in a subshell).
all_results=()

# process_node <pod> — run the balance/deposit requests against an ALREADY-OPEN forward.
# Appends one JSON record to all_results. The caller owns pf_open/pf_close.
process_node() {
    local pod=$1
    local base="http://localhost:$LOCAL_PORT"
    local deposit_amount="$AMOUNT"

    if [ "$TOPUP_TO" = true ]; then
        local balance_json current_balance
        balance_json=$(curl -s --max-time 10 "$base/chequebook/balance")
        if [ $? -ne 0 ] || [ -z "$balance_json" ]; then
            all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"balance_unavailable\"}")
            echo "  ✗ Error: Could not fetch balance"
            return
        fi

        current_balance=$(echo "$balance_json" | jq -r '.totalBalance // "0"')
        if ! [[ "$current_balance" =~ ^[0-9]+$ ]]; then
            all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"balance_parse_failed\"}")
            echo "  ✗ Error: Could not parse balance response"
            return
        fi

        if [ "$current_balance" -ge "$AMOUNT" ]; then
            all_results+=("{\"pod\":\"$pod\",\"status\":\"skipped\",\"current_balance\":\"$current_balance\",\"target\":\"$AMOUNT\"}")
            echo "  - Skipped: balance $current_balance already >= target $AMOUNT"
            return
        fi

        deposit_amount=$(( AMOUNT - current_balance ))
        echo "  Current balance: $current_balance  →  deposit needed: $deposit_amount"
    fi

    local response exit_code
    response=$(curl -v -X POST --max-time 30 --connect-timeout 10 --fail "$base/chequebook/deposit?amount=$deposit_amount" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        local response_body tx_hash
        response_body=$(echo "$response" | grep -v "^[<>*]" | tail -1)

        if echo "$response_body" | jq empty 2>/dev/null; then
            tx_hash=$(echo "$response_body" | jq -r '.transactionHash // empty')
            if [ -n "$tx_hash" ]; then
                all_results+=("{\"pod\":\"$pod\",\"status\":\"success\",\"tx_hash\":\"$tx_hash\"}")
                echo "  ✓ Success - TX: $tx_hash"
            else
                all_results+=("{\"pod\":\"$pod\",\"status\":\"success\",\"response\":$(echo "$response_body" | jq -c '.')}")
                echo "  ✓ Success - Response: $response_body"
            fi
        else
            all_results+=("{\"pod\":\"$pod\",\"status\":\"success\",\"response\":\"$response_body\"}")
            echo "  ✓ Success - Response: $response_body"
        fi
    else
        if [ $exit_code -eq 6 ] || [ $exit_code -eq 7 ] || [ $exit_code -eq 28 ]; then
            all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"endpoint_unavailable\"}")
            echo "  ✗ Error: Endpoint unavailable"
        elif [ $exit_code -eq 22 ]; then
            local http_code
            http_code=$(echo "$response" | grep "^< HTTP" | tail -1 | awk '{print $3}')
            all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"http_error\",\"http_code\":\"$http_code\"}")
            echo "  ✗ Error: HTTP $http_code"
        else
            all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"curl_exit_$exit_code\"}")
            echo "  ✗ Error: curl exit code $exit_code"
        fi
    fi
}

for pod in "${pods[@]}"; do
    pf_aborted && { echo "Stopping early (cancellation requested); summarising what ran so far."; echo ""; break; }

    echo "Processing: $pod"

    if ! pf_open "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT"; then
        all_results+=("{\"pod\":\"$pod\",\"status\":\"error\",\"error\":\"portforward_failed\"}")
        echo "  ✗ Error: Could not establish port-forward"
        pf_close
        echo ""
        continue
    fi

    process_node "$pod"

    # Always close before the next node so LOCAL_PORT is free to reopen.
    pf_close
    echo ""
done

# Build JSON array for summary
temp_json="["
for i in "${!all_results[@]}"; do
    if [ $i -ne 0 ]; then temp_json+=","; fi
    temp_json+="${all_results[$i]}"
done
temp_json+="]"

# Separate into success, skipped, and error arrays
success_json=$(echo "$temp_json" | jq 'map(select(.status == "success"))')
skipped_json=$(echo "$temp_json" | jq 'map(select(.status == "skipped"))')
error_json=$(echo "$temp_json" | jq 'map(select(.status == "error"))')

success_count=$(echo "$success_json" | jq 'length')
skipped_count=$(echo "$skipped_json" | jq 'length')
error_count=$(echo "$error_json" | jq 'length')

echo "===== SUMMARY ====="
echo "{
  \"total_nodes\": ${#pods[@]},
  \"success_count\": $success_count,
  \"success\": $success_json,
  \"skipped_count\": $skipped_count,
  \"skipped\": $skipped_json,
  \"error_count\": $error_count,
  \"errors\": $error_json
}" | jq .
