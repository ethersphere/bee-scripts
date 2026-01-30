#!/bin/bash
# Script: chequebook-deposit.sh
# Description: Executes POST request to /chequebook/deposit endpoint for each node in the namespace.

# Usage: ./chequebook-deposit.sh <namespace> <domain> <amount>

# Use passed namespace, domain, and amount
NAMESPACE=${1:-}
DOMAIN=${2:-}
AMOUNT=${3:-}

if [ -z "$NAMESPACE" ] || [ -z "$DOMAIN" ] || [ -z "$AMOUNT" ]; then
    echo "Usage: $0 <namespace> <domain> <amount>"
    echo "Example: $0 bee-testnet testnet.internal 117000000"
    exit 1
fi

# Validate amount is a number
if ! [[ "$AMOUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: amount must be a positive integer"
    exit 1
fi

# Get list of ingress hosts/IPs matching domain in the given namespace, only those starting with bee-
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}' | grep '^bee-'))

if [ ${#list[@]} -eq 0 ]; then
    echo "Error: No ingress resources found in namespace '$NAMESPACE' matching domain '$DOMAIN'"
    exit 1
fi

echo "Found ${#list[@]} bee nodes in namespace '$NAMESPACE'"
echo "Executing deposit requests with amount: $AMOUNT"
echo ""

# Arrays to hold all results
all_results=()

for url in "${list[@]}"; do
    echo "Processing: $url"
    
    # Execute POST request to /chequebook/deposit
    response=$(curl -v -X POST --max-time 30 --connect-timeout 10 --fail "http://$url/chequebook/deposit?amount=$AMOUNT" 2>&1)
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        # Extract response body (last line after headers)
        response_body=$(echo "$response" | grep -v "^[<>*]" | tail -1)
        
        # Try to parse as JSON
        if echo "$response_body" | jq empty 2>/dev/null; then
            tx_hash=$(echo "$response_body" | jq -r '.transactionHash // empty')
            if [ -n "$tx_hash" ]; then
                all_results+=("{\"ingress\":\"$url\",\"status\":\"success\",\"tx_hash\":\"$tx_hash\"}")
                echo "  ✓ Success - TX: $tx_hash"
            else
                all_results+=("{\"ingress\":\"$url\",\"status\":\"success\",\"response\":$(echo "$response_body" | jq -c '.')}")
                echo "  ✓ Success - Response: $response_body"
            fi
        else
            all_results+=("{\"ingress\":\"$url\",\"status\":\"success\",\"response\":\"$response_body\"}")
            echo "  ✓ Success - Response: $response_body"
        fi
    else
        # Handle error cases
        if [ $exit_code -eq 6 ] || [ $exit_code -eq 7 ] || [ $exit_code -eq 28 ]; then
            all_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":\"endpoint_unavailable\"}")
            echo "  ✗ Error: Endpoint unavailable"
        elif [ $exit_code -eq 22 ]; then
            # HTTP error - try to extract status code
            http_code=$(echo "$response" | grep "^< HTTP" | tail -1 | awk '{print $3}')
            all_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":\"http_error\",\"http_code\":\"$http_code\"}")
            echo "  ✗ Error: HTTP $http_code"
        else
            all_results+=("{\"ingress\":\"$url\",\"status\":\"error\",\"error\":\"curl_exit_$exit_code\"}")
            echo "  ✗ Error: curl exit code $exit_code"
        fi
    fi
    echo ""
done

# Build JSON array for summary
temp_json="["
for i in "${!all_results[@]}"; do
    if [ $i -ne 0 ]; then temp_json+=","; fi
    temp_json+="${all_results[$i]}"
done
temp_json+="]"

# Separate into success and error arrays
success_json=$(echo "$temp_json" | jq 'map(select(.status == "success"))')
error_json=$(echo "$temp_json" | jq 'map(select(.status == "error"))')

# Get counts
success_count=$(echo "$success_json" | jq 'length')
error_count=$(echo "$error_json" | jq 'length')

# Build final JSON output
echo "===== SUMMARY ====="
echo "{
  \"total_nodes\": ${#list[@]},
  \"success_count\": $success_count,
  \"success\": $success_json,
  \"error_count\": $error_count,
  \"errors\": $error_json
}" | jq .
