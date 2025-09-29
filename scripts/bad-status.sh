#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

for i in ${!list[@]};
do
    url=${list[$i]}
    result=$(curl $url/status/peers -s) 
    peers=( $(echo $result | jq -c '.snapshots[]') )
    # peers=( $(echo $result | jq -c '.snapshots[] | select(.storageRadius != 10 or .neighborhoodSize < 1 ) ') )
    peers=( $(echo $result | jq -c '.snapshots[] | select(.batchCommitment != 99715645440 ) ') )
    for j in ${!peers[@]};
    do
        peer=${peers[$j]}
        echo $peer >> bad-peers.json
        echo $url >> bad-peers.json
        overlay=$(echo $peer | jq -c '.peer' | tr -d '"')
        curl -s https://api.swarmscan.io/v1/network/nodes/$overlay | jq '.location.country' >> bad-peers.json
    done
done


# ./scripts/bad-status.sh bee-gateway && ./scripts/bad-status.sh bee-storage && ./scripts/bad-status.sh dev-bee-gateway && ./scripts/bad-status.sh dev-bee-storage && ./scripts/bad-status.sh bee-bootnode && ./scripts/bad-status.sh dev-bee-bootnode
