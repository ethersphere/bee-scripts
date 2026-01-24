#!/bin/bash
# Script: check-peers-overlay.sh
# Description: Queries each node in the namespace for /peers endpoint and checks for a specified overlay address.

# Usage: ./check-peers-overlay.sh <namespace> <domain> <overlay_address>

# Use passed namespace and domain, or defaults
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}
OVERLAY=${3:-}

if [ -z "$OVERLAY" ]; then
    echo "Usage: $0 <namespace> <domain> <overlay_address>"
    exit 1
fi

# Get list of ingress hosts/IPs matching domain in the given namespace, only those starting with bee-
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}' | grep '^bee-'))

if [ ${#list[@]} -eq 0 ]; then
    exit 1
fi

# Arrays to hold all results before deduplication
all_results=()

for url in "${list[@]}"; do
    # Get node's own overlay from /status endpoint
    status_response=$(curl -s --max-time 10 --connect-timeout 5 --fail "$url/status" 2>/dev/null)
    status_exit_code=$?
    if [ $status_exit_code -ne 0 ]; then
        if [ $status_exit_code -eq 6 ] || [ $status_exit_code -eq 7 ] || [ $status_exit_code -eq 28 ]; then
            all_results+=("{\"ingress\":\"$url\",\"error\":\"endpoint_unavailable\",\"has_search_overlay\":false}")
        else
            all_results+=("{\"ingress\":\"$url\",\"error\":\"status_curl_$status_exit_code\",\"has_search_overlay\":false}")
        fi
        continue
    fi
    if ! echo "$status_response" | jq empty 2>/dev/null; then
        all_results+=("{\"ingress\":\"$url\",\"error\":\"status_invalid_json\",\"has_search_overlay\":false}")
        continue
    fi
    node_overlay=$(echo "$status_response" | jq -r '.overlay // empty')
    
    # Query /peers endpoint to check for search overlay
    peers_response=$(curl -s --max-time 10 --connect-timeout 5 --fail "$url/peers" 2>/dev/null)
    peers_exit_code=$?
    if [ $peers_exit_code -ne 0 ]; then
        if [ $peers_exit_code -eq 6 ] || [ $peers_exit_code -eq 7 ] || [ $peers_exit_code -eq 28 ]; then
            all_results+=("{\"ingress\":\"$url\",\"node_overlay\":\"$node_overlay\",\"error\":\"endpoint_unavailable\",\"has_search_overlay\":false}")
        else
            all_results+=("{\"ingress\":\"$url\",\"node_overlay\":\"$node_overlay\",\"error\":\"peers_curl_$peers_exit_code\",\"has_search_overlay\":false}")
        fi
        continue
    fi
    if ! echo "$peers_response" | jq empty 2>/dev/null; then
        all_results+=("{\"ingress\":\"$url\",\"node_overlay\":\"$node_overlay\",\"error\":\"peers_invalid_json\",\"has_search_overlay\":false}")
        continue
    fi
    
    # Check if search overlay is present in peers
    if echo "$peers_response" | jq -r '.peers[].address' 2>/dev/null | grep -q "$OVERLAY"; then
        all_results+=("{\"ingress\":\"$url\",\"node_overlay\":\"$node_overlay\",\"has_search_overlay\":true}")
    else
        all_results+=("{\"ingress\":\"$url\",\"node_overlay\":\"$node_overlay\",\"has_search_overlay\":false}")
    fi
done

# Build temporary JSON array for processing
temp_json="["
for i in "${!all_results[@]}"; do
    if [ $i -ne 0 ]; then temp_json+=","; fi
    temp_json+="${all_results[$i]}"
done
temp_json+="]"

# Process with jq to deduplicate by node_overlay and prefer longer ingress names
processed_json=$(echo "$temp_json" | jq -c '
group_by(.node_overlay // ("error_" + (.ingress // ""))) |
map(
  if length > 1 and .[0].node_overlay and .[0].node_overlay != "" then
    # Multiple entries with same overlay - prefer longer ingress name
    sort_by(.ingress | length) | reverse | .[0]
  else
    .[0]
  end
)' 2>/dev/null)

# If jq fails, fall back to original array
if [ $? -ne 0 ] || [ -z "$processed_json" ]; then
    processed_json="$temp_json"
fi

# Separate into found, not_found, and unavailable arrays
found_json=$(echo "$processed_json" | jq 'map(select(.has_search_overlay == true and (.error | not))) | map(del(.has_search_overlay))')
not_found_json=$(echo "$processed_json" | jq 'map(select(.has_search_overlay == false and (.error | not))) | map(del(.has_search_overlay))')
unavailable_json=$(echo "$processed_json" | jq 'map(select(.error == "endpoint_unavailable")) | map(del(.has_search_overlay))')
other_errors_json=$(echo "$processed_json" | jq 'map(select(.error and .error != "endpoint_unavailable")) | map(del(.has_search_overlay))')

# Get counts and build final output
found_count=$(echo "$found_json" | jq 'length')
not_found_count=$(echo "$not_found_json" | jq 'length')
unavailable_count=$(echo "$unavailable_json" | jq 'length')
other_errors_count=$(echo "$other_errors_json" | jq 'length')

# Build final JSON output
echo "{
  \"found_count\": $found_count,
  \"found\": $found_json,
  \"not_found_count\": $not_found_count,
  \"not_found\": $not_found_json,
  \"unavailable_count\": $unavailable_count,
  \"unavailable_endpoints\": $unavailable_json,
  \"other_errors_count\": $other_errors_count,
  \"other_errors\": $other_errors_json
}" | jq .
