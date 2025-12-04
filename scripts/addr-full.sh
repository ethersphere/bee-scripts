#!/bin/bash

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

# Get list of ingress hosts/IPs matching "testnet.internal" in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

# Initialize JSON array
json_array="["
first=true

for i in ${!list[@]};
do
    url=${list[$i]}
    response=$(curl -s "$url/addresses")
    
    # Extract only overlay, underlay, and ethereum from the response
    overlay=$(echo "$response" | jq -r '.overlay // empty')
    underlay=$(echo "$response" | jq -r '.underlay // empty')
    ethereum=$(echo "$response" | jq -r '.ethereum // empty')
    
    # Add comma if not first item
    if [ "$first" = false ]; then
        json_array+=","
    fi
    first=false
    
    # Build JSON object with ingress name, overlay, underlay, and ethereum
    json_array+=$(jq -n \
        --arg ingress "$url" \
        --arg overlay "$overlay" \
        --argjson underlay "$(echo "$response" | jq '.underlay // []')" \
        --arg ethereum "$ethereum" \
        '{ingress: $ingress, overlay: $overlay, underlay: $underlay, ethereum: $ethereum}')
done

json_array+="]"

# Deduplicate by overlay address (since some ingresses are load balancing)
# Wrap in JSON object with count and results array
echo "$json_array" | jq 'group_by(.overlay) | map(.[0]) | {count: length, results: .}'
