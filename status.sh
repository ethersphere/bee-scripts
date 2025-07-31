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
    # peers=( $(echo $result | jq -c '.snapshots[]') )
    peers=( $(echo $result | jq -c '.snapshots[]') )
    for j in ${!peers[@]};
    do
        peer=${peers[$j]}
        echo $peer >> status.json
        echo $url >> status.json
    done
done


# ./scripts/status.sh bee-gateway && ./scripts/status.sh bee-storage && ./scripts/status.sh dev-bee-gateway && ./scripts/status.sh dev-bee-storage && ./scripts/status.sh bee-bootnode && ./scripts/status.sh dev-bee-bootnode
