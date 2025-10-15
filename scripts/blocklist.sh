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
    addr=$(curl $url/blocklist -s | jq )
    echo "$url $addr"
done
