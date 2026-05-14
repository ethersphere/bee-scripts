#!/bin/bash

# Retrieves chequebook balance from each Bee node in a Kubernetes namespace.
# Flags nodes below the minimum chequebook threshold (11 BZZ = 1.1e17 token units).
# Usage: ./chequebook-balance-get.sh [NAMESPACE] [DOMAIN]
# Example: ./chequebook-balance-get.sh bee-light-testnet lightnet.testnet.internal

NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

# 11 BZZ expressed in token units (1 BZZ = 1e16 token units for display, 1.1e17 raw)
MIN_BALANCE=110000000000000000

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"
echo "Minimum required balance: 11.00 BZZ (${MIN_BALANCE} token units)"
echo ""

list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}' | grep '^bee-[0-9]'))

if [ ${#list[@]} -eq 0 ]; then
    echo "Error: No ingress resources found in namespace '$NAMESPACE' matching domain '$DOMAIN'"
    exit 1
fi

counter=0
below_min=0

for url in "${list[@]}"; do
    json_data=$(curl -s --max-time 10 "$url/chequebook/balance")
    if [ $? -ne 0 ] || [ -z "$json_data" ]; then
        printf '%-50s | ERROR: could not reach /chequebook/balance\n' "$url"
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

    printf '%-50s | total: %8.2f BZZ  available: %8.2f BZZ%s\n' \
        "$url" "$total_bzz" "$avail_bzz" "$flag"

    ((counter++))
done

echo ""
echo "Total processed: $counter  |  Below minimum (11 BZZ): $below_min"
