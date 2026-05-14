#!/bin/bash
# Script: chequebook-cashout-withdraw.sh
# Description: Cashes out all peer cheques and withdraws the full chequebook balance
#              to the node wallet. Run this before nuking overlays to preserve funds.

# Usage: ./chequebook-cashout-withdraw.sh <namespace> <domain> [cashout_wait_seconds]

NAMESPACE=${1:-}
DOMAIN=${2:-}
CASHOUT_WAIT=${3:-60}

if [ -z "$NAMESPACE" ] || [ -z "$DOMAIN" ]; then
    echo "Usage: $0 <namespace> <domain> [cashout_wait_seconds]"
    echo "Example: $0 bee-testnet testnet.internal 60"
    exit 1
fi

if ! [[ "$CASHOUT_WAIT" =~ ^[0-9]+$ ]]; then
    echo "Error: cashout_wait_seconds must be a positive integer"
    exit 1
fi

list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}' | grep '^bee-'))

if [ ${#list[@]} -eq 0 ]; then
    echo "Error: No ingress resources found in namespace '$NAMESPACE' matching domain '$DOMAIN'"
    exit 1
fi

echo "Found ${#list[@]} bee nodes in namespace '$NAMESPACE'"
echo ""

cashout_results=()
withdraw_results=()

# Step 1: cash out all peer cheques on every node
echo "===== STEP 1: CASHOUT ====="
for url in "${list[@]}"; do
    echo "Processing: $url"

    peers_json=$(curl -s --max-time 30 --connect-timeout 10 "http://$url/chequebook/cheque")
    if [ $? -ne 0 ] || [ -z "$peers_json" ]; then
        cashout_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":\"failed to fetch cheques\"}")
        echo "  ✗ Error: could not reach /chequebook/cheque"
        echo ""
        continue
    fi

    peers=$(echo "$peers_json" | jq -r '.lastcheques // [] | .[].peer')
    peer_count=$(echo "$peers" | grep -c . || true)

    if [ -z "$peers" ]; then
        cashout_results+=("{\"ingress\":\"$url\",\"status\":\"skipped\",\"reason\":\"no peers with cheques\"}")
        echo "  - No peers with cheques, skipping"
        echo ""
        continue
    fi

    node_cashouts=()
    for peer in $peers; do
        cashout_status=$(curl -s --max-time 30 --connect-timeout 10 "http://$url/chequebook/cashout/$peer")
        uncashed=$(echo "$cashout_status" | jq -r '.uncashedAmount // "0"')

        if [ "$uncashed" = "0" ] || [ "$uncashed" = "null" ] || [ -z "$uncashed" ]; then
            echo "  - Peer $peer: nothing to cash out"
            continue
        fi

        echo "  + Peer $peer: uncashed $uncashed, cashing out..."
        response=$(curl -s -X POST --max-time 30 --connect-timeout 10 "http://$url/chequebook/cashout/$peer")
        tx_hash=$(echo "$response" | jq -r '.transactionHash // empty')

        if [ -n "$tx_hash" ]; then
            node_cashouts+=("{\"peer\":\"$peer\",\"uncashed\":$uncashed,\"tx\":\"$tx_hash\"}")
            echo "    ✓ TX: $tx_hash"
        else
            node_cashouts+=("{\"peer\":\"$peer\",\"uncashed\":$uncashed,\"error\":\"no tx hash\"}")
            echo "    ✗ Error: no transaction hash in response"
        fi
    done

    # Build cashout summary for this node
    cashouts_json="["
    for i in "${!node_cashouts[@]}"; do
        if [ $i -ne 0 ]; then cashouts_json+=","; fi
        cashouts_json+="${node_cashouts[$i]}"
    done
    cashouts_json+="]"

    cashout_results+=("{\"ingress\":\"$url\",\"status\":\"ok\",\"cashouts\":$cashouts_json}")
    echo ""
done

# Step 2: wait for cashout transactions to land
if [ "$CASHOUT_WAIT" -gt 0 ]; then
    echo "===== WAITING ${CASHOUT_WAIT}s FOR CASHOUT TRANSACTIONS TO CONFIRM ====="
    sleep "$CASHOUT_WAIT"
    echo ""
fi

# Step 3: withdraw full available balance from each node's chequebook
echo "===== STEP 2: WITHDRAW ====="
for url in "${list[@]}"; do
    echo "Processing: $url"

    balance_json=$(curl -s --max-time 30 --connect-timeout 10 "http://$url/chequebook/balance")
    if [ $? -ne 0 ] || [ -z "$balance_json" ]; then
        withdraw_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":\"failed to fetch balance\"}")
        echo "  ✗ Error: could not reach /chequebook/balance"
        echo ""
        continue
    fi

    available=$(echo "$balance_json" | jq -r '.availableBalance // "0"')

    if [ "$available" = "0" ] || [ "$available" = "null" ] || [ -z "$available" ]; then
        withdraw_results+=("{\"ingress\":\"$url\",\"status\":\"skipped\",\"reason\":\"zero available balance\"}")
        echo "  - Available balance: 0, skipping"
        echo ""
        continue
    fi

    echo "  + Available balance: $available, withdrawing..."
    response=$(curl -s -X POST --max-time 30 --connect-timeout 10 "http://$url/chequebook/withdraw?amount=$available")
    tx_hash=$(echo "$response" | jq -r '.transactionHash // empty')

    if [ -n "$tx_hash" ]; then
        withdraw_results+=("{\"ingress\":\"$url\",\"status\":\"success\",\"amount\":$available,\"tx_hash\":\"$tx_hash\"}")
        echo "  ✓ Withdrew $available — TX: $tx_hash"
    else
        withdraw_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":$(echo "$response" | jq -c '. // "empty response"')}")
        echo "  ✗ Error: $(echo "$response" | jq -c '.')"
    fi
    echo ""
done

# Summary
build_json_array() {
    local arr=("$@")
    local out="["
    for i in "${!arr[@]}"; do
        if [ $i -ne 0 ]; then out+=","; fi
        out+="${arr[$i]}"
    done
    out+="]"
    echo "$out"
}

cashout_json=$(build_json_array "${cashout_results[@]}")
withdraw_json=$(build_json_array "${withdraw_results[@]}")

withdraw_success=$(echo "$withdraw_json" | jq 'map(select(.status == "success")) | length')
withdraw_error=$(echo "$withdraw_json" | jq 'map(select(.status == "error")) | length')
withdraw_skipped=$(echo "$withdraw_json" | jq 'map(select(.status == "skipped")) | length')

echo "===== SUMMARY ====="
echo "{
  \"total_nodes\": ${#list[@]},
  \"cashouts\": $cashout_json,
  \"withdrawals\": {
    \"success_count\": $withdraw_success,
    \"error_count\": $withdraw_error,
    \"skipped_count\": $withdraw_skipped,
    \"details\": $withdraw_json
  }
}" | jq .
