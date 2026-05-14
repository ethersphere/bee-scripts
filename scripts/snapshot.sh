#!/bin/bash

# Pre-upgrade baseline snapshot: version, overlay, ethereum, chequebook address,
# chequebook balance, and wallet balance for every node in a namespace.
# Satisfies Phase 0 documentation requirements for chequebook verification testing.
#
# Usage: ./snapshot.sh [NAMESPACE] [DOMAIN] [OUTPUT_FILE]
# Example: ./snapshot.sh bee-light-testnet lightnet.testnet.internal snapshot-before.json

NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}
OUTPUT_FILE=${3:-}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"
[ -n "$OUTPUT_FILE" ] && echo "Output file: $OUTPUT_FILE"
echo ""

# Pre-fetch pod→image mapping once (pod name = first hostname component)
# Stored as tab-separated lines; looked up per-node with awk (bash 3 compatible)
pod_images=$(kubectl get pods -n "$NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}' \
    2>/dev/null)

list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}' | grep '^bee-[0-9]'))

if [ ${#list[@]} -eq 0 ]; then
    echo "Error: No ingress resources found in namespace '$NAMESPACE' matching domain '$DOMAIN'"
    exit 1
fi

results="["
first=true
errors=0

for url in "${list[@]}"; do
    pod_name=$(echo "$url" | cut -d. -f1)
    image=$(echo "$pod_images" | awk -v pod="$pod_name" '$1 == pod {print $2; exit}')
    image=${image:-unknown}

    # Fetch all endpoints
    health=$(curl -s --max-time 10 "$url/health")
    addresses=$(curl -s --max-time 10 "$url/addresses")
    cheque_addr=$(curl -s --max-time 10 "$url/chequebook/address")
    cheque_bal=$(curl -s --max-time 10 "$url/chequebook/balance")
    wallet=$(curl -s --max-time 10 "$url/wallet")
    node_status=$(curl -s --max-time 10 "$url/status")
    peer_status=$(curl -s --max-time 10 "$url/status/peers")

    version=$(echo "$health" | jq -r '.version // "error"')
    overlay=$(echo "$addresses" | jq -r '.overlay // "error"')
    ethereum=$(echo "$addresses" | jq -r '.ethereum // "error"')
    chequebook=$(echo "$cheque_addr" | jq -r '.chequebookAddress // "none"')

    total_raw=$(echo "$cheque_bal" | jq -r '.totalBalance // "0"')
    avail_raw=$(echo "$cheque_bal" | jq -r '.availableBalance // "0"')
    bzz_raw=$(echo "$wallet" | jq -r '.bzzBalance // "0"')
    native_raw=$(echo "$wallet" | jq -r '.nativeTokenBalance // "0"')

    total_bzz=$(echo "scale=2; ${total_raw:-0} / 10000000000000000" | bc 2>/dev/null || echo "0")
    avail_bzz=$(echo "scale=2; ${avail_raw:-0} / 10000000000000000" | bc 2>/dev/null || echo "0")
    wallet_bzz=$(echo "scale=2; ${bzz_raw:-0} / 10000000000000000" | bc 2>/dev/null || echo "0")
    wallet_native=$(echo "scale=6; ${native_raw:-0} / 1000000000000000000" | bc 2>/dev/null || echo "0")

    connected_peers=$(echo "$node_status" | jq -r '.connectedPeers // 0')
    is_reachable=$(echo "$node_status" | jq -r '.isReachable // false')
    storage_radius=$(echo "$node_status" | jq -r '.storageRadius // 0')
    pullsync_rate=$(echo "$node_status" | jq -r '.pullsyncRate // 0')
    peer_overlays=$(echo "$peer_status" | jq -c '[.snapshots[]?.overlay] // []')

    if [ "$first" = false ]; then results+=","; fi
    first=false

    entry=$(jq -n \
        --arg node "$url" \
        --arg image "$image" \
        --arg version "$version" \
        --arg overlay "$overlay" \
        --arg ethereum "$ethereum" \
        --arg chequebook "$chequebook" \
        --arg chequebook_total_bzz "$total_bzz" \
        --arg chequebook_avail_bzz "$avail_bzz" \
        --arg chequebook_total_raw "$total_raw" \
        --arg wallet_bzz "$wallet_bzz" \
        --arg wallet_native "$wallet_native" \
        --argjson connected_peers "$connected_peers" \
        --argjson is_reachable "$is_reachable" \
        --argjson storage_radius "$storage_radius" \
        --argjson pullsync_rate "$pullsync_rate" \
        --argjson peer_overlays "$peer_overlays" \
        '{
            node: $node,
            image: $image,
            version: $version,
            overlay: $overlay,
            ethereum: $ethereum,
            chequebook_address: $chequebook,
            chequebook_balance: {
                total_bzz: ($chequebook_total_bzz | tonumber),
                available_bzz: ($chequebook_avail_bzz | tonumber),
                total_raw: $chequebook_total_raw
            },
            wallet_balance: {
                bzz: ($wallet_bzz | tonumber),
                native: ($wallet_native | tonumber)
            },
            status: {
                connected_peers: $connected_peers,
                is_reachable: $is_reachable,
                storage_radius: $storage_radius,
                pullsync_rate: $pullsync_rate,
                peer_overlays: $peer_overlays
            }
        }')

    results+="$entry"

    # Human-readable per-node summary
    printf 'Node:        %s\n' "$url"
    printf '  Image:     %s\n' "$image"
    printf '  Version:   %s\n' "$version"
    printf '  Overlay:   %s\n' "$overlay"
    printf '  Ethereum:  %s\n' "$ethereum"
    printf '  Chequebook:%s\n' "$chequebook"
    printf '  CB balance: total=%s BZZ  available=%s BZZ  (raw: %s)\n' "$total_bzz" "$avail_bzz" "$total_raw"
    printf '  Wallet:     bzz=%s BZZ  native=%s\n' "$wallet_bzz" "$wallet_native"
    printf '  Peers:      connected=%s  reachable=%s  radius=%s  pullsync=%.2f/s\n' \
        "$connected_peers" "$is_reachable" "$storage_radius" "$pullsync_rate"
    echo ""
done

results+="]"

snapshot=$(jq -n \
    --arg ts "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --arg ns "$NAMESPACE" \
    --arg domain "$DOMAIN" \
    --argjson nodes "$results" \
    '{
        snapshot_time: $ts,
        namespace: $ns,
        domain: $domain,
        node_count: ($nodes | length),
        nodes: $nodes
    }')

echo "===== SUMMARY ====="
echo "$snapshot" | jq '{snapshot_time, namespace, node_count,
    min_chequebook_bzz: ([.nodes[].chequebook_balance.total_bzz] | min),
    max_chequebook_bzz: ([.nodes[].chequebook_balance.total_bzz] | max),
    versions: ([.nodes[].version] | unique),
    images: ([.nodes[].image] | unique),
    peer_counts: ([.nodes[].status.connected_peers] | {min: min, max: max, avg: (add / length | round)}),
    reachable_count: ([.nodes[] | select(.status.is_reachable == true)] | length)
}'

if [ -n "$OUTPUT_FILE" ]; then
    echo "$snapshot" > "$OUTPUT_FILE"
    echo ""
    echo "Full snapshot written to: $OUTPUT_FILE"
fi
