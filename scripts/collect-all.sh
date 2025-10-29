#!/bin/bash

# This script combines status-peers.sh, overlay.sh functionality and collects pod logs
# for a given Kubernetes namespace, saving all outputs to a specified target folder.
# Usage: ./collect-all.sh [NAMESPACE] [DOMAIN] [TARGET_FOLDER]
# Example: ./collect-all.sh bee-testnet testnet.internal ./output

# Use passed parameters or defaults
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}
TARGET_FOLDER=${3:-./output}

echo "=========================================="
echo "🐝 Bee Scripts Collection Tool"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Domain: $DOMAIN"
echo "Target folder: $TARGET_FOLDER"
echo ""

# Create target folder if it doesn't exist
mkdir -p "$TARGET_FOLDER"

# Function to get timestamp for filenames
get_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

TIMESTAMP=$(get_timestamp)

echo "📁 Created target folder: $TARGET_FOLDER"
echo ""

# 1. Execute status-peers.sh functionality
echo "🔍 Collecting connected peers status..."
echo "----------------------------------------"
status_file="$TARGET_FOLDER/status-peers_${TIMESTAMP}.txt"

{
    echo "Status Peers Collection - $(date)"
    echo "Namespace: $NAMESPACE"
    echo "Domain: $DOMAIN"
    echo "========================================"
    echo ""
    
    # Get list of ingress hosts/IPs matching the domain in the given namespace
    list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))
    
    counter=0
    successful_requests=0
    
    echo "Fetching connected peers count from all ingress endpoints..."
    echo "=========================================================="
    
    for url in "${list[@]}"; do
        echo "Processing: $url"
        
        # Fetch the JSON data from the curl command
        json_data=$(curl -s "${url}/status")
        
        # Check if the request was successful
        if [ $? -ne 0 ] || [ -z "$json_data" ]; then
            echo "  ❌ Failed to fetch data from $url"
            continue
        fi
        
        # Extract connectedPeers count
        connected_peers=$(echo "$json_data" | jq -r '.connectedPeers // "N/A"')
        
        if [ "$connected_peers" = "N/A" ] || [ "$connected_peers" = "null" ]; then
            echo "  ⚠️  No connectedPeers field found in response from $url"
            continue
        fi
        
        # Display the count if it's a number
        if [[ "$connected_peers" =~ ^[0-9]+$ ]]; then
            echo "  👥 Connected peers: $connected_peers"
            ((successful_requests++))
        else
            echo "  ⚠️  Invalid connectedPeers value: $connected_peers"
        fi
        
        ((counter++))
    done
    
    echo "=========================================================="
    echo "📈 SUMMARY:"
    echo "Total endpoints processed: $counter"
    echo "Successful requests: $successful_requests"
    echo ""
    echo "✅ Status peers analysis complete!"
    
} > "$status_file"

echo "✅ Status peers data saved to: $status_file"
echo ""

# 2. Execute overlay.sh functionality
echo "🌐 Collecting overlay addresses..."
echo "----------------------------------"
overlay_file="$TARGET_FOLDER/overlay_${TIMESTAMP}.txt"

{
    echo "Overlay Addresses Collection - $(date)"
    echo "Namespace: $NAMESPACE"
    echo "Domain: $DOMAIN"
    echo "========================================"
    echo ""
    
    # Get list of ingress hosts/IPs matching the domain in the given namespace
    list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))
    
    for i in ${!list[@]};
    do
        url=${list[$i]}
        echo "Processing: $url"
        addr=$(curl "$url/addresses" -s | jq '.overlay')
        echo "$url $addr"
        echo ""
    done
    
    echo "✅ Overlay addresses collection complete!"
    
} > "$overlay_file"

echo "✅ Overlay data saved to: $overlay_file"
echo ""

# 3. Collect logs from all pods in the namespace
echo "📋 Collecting pod logs..."
echo "-------------------------"

# Get list of all pods in the namespace
pods=($(kubectl get pods -n "$NAMESPACE" --no-headers -o custom-columns=":metadata.name"))

if [ ${#pods[@]} -eq 0 ]; then
    echo "⚠️  No pods found in namespace: $NAMESPACE"
    logs_file="$TARGET_FOLDER/pod-logs_${TIMESTAMP}.txt"
    echo "No pods found in namespace: $NAMESPACE" > "$logs_file"
else
    echo "Found ${#pods[@]} pod(s) in namespace: $NAMESPACE"
    
    for pod in "${pods[@]}"; do
        echo "Collecting logs from pod: $pod"
        log_file="$TARGET_FOLDER/pod-${pod}_${TIMESTAMP}.log"
        
        # Collect logs from the pod
        kubectl logs -n "$NAMESPACE" "$pod" > "$log_file" 2>&1
        
        if [ $? -eq 0 ]; then
            echo "  ✅ Logs saved to: $log_file"
        else
            echo "  ❌ Failed to collect logs from pod: $pod"
        fi
    done
fi

echo ""

# 4. Create a summary file
echo "📊 Creating summary..."
summary_file="$TARGET_FOLDER/collection-summary_${TIMESTAMP}.txt"

{
    echo "Bee Scripts Collection Summary"
    echo "=============================="
    echo "Collection time: $(date)"
    echo "Namespace: $NAMESPACE"
    echo "Domain: $DOMAIN"
    echo "Target folder: $TARGET_FOLDER"
    echo ""
    echo "Files created:"
    echo "- Status peers: status-peers_${TIMESTAMP}.txt"
    echo "- Overlay addresses: overlay_${TIMESTAMP}.txt"
    echo "- Pod logs: pod-<podname>_${TIMESTAMP}.log (${#pods[@]} files)"
    echo ""
    echo "Collection completed successfully!"
    
} > "$summary_file"

echo "✅ Summary saved to: $summary_file"
echo ""

echo "=========================================="
echo "🎉 Collection completed successfully!"
echo "=========================================="
echo "All outputs saved to: $TARGET_FOLDER"
echo "Summary file: $summary_file"
echo ""
