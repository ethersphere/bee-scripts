#!/bin/bash

# This script retrieves neighborhood information from multiple Bee nodes in a specified Kubernetes namespace.
# It requires 'kubectl', 'curl', and 'jq' to be installed on the system.
# Usage: ./neighborhoods.sh [NAMESPACE] [DOMAIN]
# Example: ./neighborhoods.sh bee-testnet testnet.internal

# Use passed namespace, or default to 'bee-testnet'
NAMESPACE=${1:-bee-testnet}
DOMAIN=${2:-testnet.internal}

echo "Using namespace: $NAMESPACE with domain: $DOMAIN"

# Get list of ingress hosts/IPs matching the domain in the given namespace
list=($(kubectl get ingress -n "$NAMESPACE" | grep "$DOMAIN" | awk '{print $3}'))

counter=0
total_neighborhoods=0
unique_neighborhoods=()

echo "Fetching neighborhoods from all ingress endpoints..."
echo "=================================================="

for url in "${list[@]}"; do
  echo "Processing: $url"
  
  # Fetch the JSON data from the curl command
  json_data=$(curl -s "${url}/status/neighborhoods")
  
  # Check if the request was successful
  if [ $? -ne 0 ] || [ -z "$json_data" ]; then
    echo "  ❌ Failed to fetch data from $url"
    continue
  fi
  
  # Extract neighborhoods array
  neighborhoods=$(echo "$json_data" | jq -r '.neighborhoods[]?')
  
  if [ -z "$neighborhoods" ]; then
    echo "  ⚠️  No neighborhoods found in response from $url"
    continue
  fi
  
  # Count neighborhoods for this endpoint
  neighborhood_count=$(echo "$json_data" | jq -r '.neighborhoods | length')
  total_neighborhoods=$((total_neighborhoods + neighborhood_count))
  
  echo "  📊 Found $neighborhood_count neighborhoods"
  
  # Extract unique neighborhood identifiers
  while IFS= read -r neighborhood; do
    if [ -n "$neighborhood" ]; then
      # Check if this neighborhood is already in our unique list
      if [[ ! " ${unique_neighborhoods[@]} " =~ " ${neighborhood} " ]]; then
        unique_neighborhoods+=("$neighborhood")
      fi
    fi
  done <<< "$(echo "$json_data" | jq -r '.neighborhoods[].neighborhood')"
  
  ((counter++))
done

echo "=================================================="
echo "📈 SUMMARY:"
echo "Total endpoints processed: $counter"
echo "Total neighborhoods found: $total_neighborhoods"
echo "Unique neighborhoods: ${#unique_neighborhoods[@]}"

if [ ${#unique_neighborhoods[@]} -gt 0 ]; then
  echo ""
  echo "🔍 UNIQUE NEIGHBORHOODS (as integers):"
  for i in "${!unique_neighborhoods[@]}"; do
    neighborhood="${unique_neighborhoods[$i]}"
    # Convert binary string to integer
    if [[ "$neighborhood" =~ ^[01]+$ ]]; then
      # Convert binary to decimal using bc for large numbers
      decimal_value=$(echo "ibase=2; $neighborhood" | bc 2>/dev/null)
      if [ $? -eq 0 ] && [ -n "$decimal_value" ]; then
        # Convert back to binary to show the full representation
        binary_representation=$(echo "obase=2; $decimal_value" | bc 2>/dev/null)
        echo "  $((i+1)). $decimal_value (binary: $binary_representation)"
      else
        # Fallback to original binary if conversion fails
        echo "  $((i+1)). $neighborhood"
      fi
    else
      # For non-binary strings, show as-is
      echo "  $((i+1)). $neighborhood"
    fi
  done
fi

echo ""
echo "✅ Analysis complete!"
