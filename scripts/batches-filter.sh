#!/bin/bash

# This script queries the /stamps endpoint of every Bee node in a Kubernetes namespace
# (via the per-pod ingress hosts) and lists the postage batches whose depth is greater
# than MIN_DEPTH, optionally also keeping only those whose utilizationRatio is greater
# than MIN_RATIO. Batches are de-duplicated by batchID across nodes.
#
# It queries /stamps (not /batches) because utilizationRatio / utilization are only
# reported per owned batch by /stamps; /batches carries depth but no utilization data.
#
# It requires 'kubectl', 'curl', and 'jq' to be installed on the system.
#
# Usage: ./batches-filter.sh [MIN_DEPTH] [MIN_RATIO] [NAMESPACE] [DOMAIN]
# Defaults: MIN_DEPTH=21  MIN_RATIO=0.5  NAMESPACE=bee-testnet  DOMAIN=testnet.internal
#
# Examples:
#   ./batches-filter.sh                 # depth > 21 and utilizationRatio > 0.5
#   ./batches-filter.sh 23              # depth > 23 and utilizationRatio > 0.5
#   ./batches-filter.sh 21 0.9          # depth > 21 and utilizationRatio > 0.9
#   ./batches-filter.sh 23 -1           # depth > 23, any utilization (filter disabled)
#   ./batches-filter.sh 21 0.5 bee-staging testnet.internal

set -o pipefail

# Keep batches with depth strictly greater than this (default 21 -> depth >= 22).
MIN_DEPTH=${1:-21}
# Keep batches with utilizationRatio strictly greater than this (default 0.5).
# Pass a negative value (e.g. -1) to disable the utilization filter entirely.
MIN_RATIO=${2:-0.5}
NAMESPACE=${3:-bee-testnet}
DOMAIN=${4:-testnet.internal}

echo "Namespace: $NAMESPACE | domain: $DOMAIN | filter: depth > $MIN_DEPTH, utilizationRatio > $MIN_RATIO"

# Per-pod ingress hosts (e.g. bee-1-0.bee-testnet.testnet.internal). The per-cluster
# aggregate hosts (bee-1.*) are skipped: they round-robin to one of the pods and would
# only add redundant fetches.
hosts=($(kubectl get ingress -n "$NAMESPACE" --no-headers 2>/dev/null \
  | awk '{print $3}' | grep -E "^bee-[0-9]+-[0-9]+\..*${DOMAIN}\$" | sort -u))

if [ ${#hosts[@]} -eq 0 ]; then
  echo "No per-pod ingress hosts found in namespace '$NAMESPACE' matching '$DOMAIN'." >&2
  exit 1
fi

echo "Querying ${#hosts[@]} nodes..."

raw=$(mktemp)
trap 'rm -f "$raw"' EXIT

# Fetch /stamps from every node, tagging each batch with the host that owns it.
for host in "${hosts[@]}"; do
  json=$(curl -s -f -m 8 "http://${host}/stamps") || { echo "  ! $host unreachable, skipping" >&2; continue; }
  echo "$json" | jq -c --arg host "$host" \
    '.stamps[]? | {host: $host, batchID, depth, utilizationRatio, utilization, amount, batchTTL, label}' >> "$raw"
done

# De-dupe by batchID, apply the filters, sort by depth (desc) then utilizationRatio (desc).
result=$(jq -s \
  --argjson md "$MIN_DEPTH" \
  --argjson mr "$MIN_RATIO" '
    unique_by(.batchID)
    | map(select(.depth > $md and (.utilizationRatio // 0) > $mr))
    | sort_by(-.depth, -(.utilizationRatio // 0))
  ' "$raw")

count=$(echo "$result" | jq 'length')

# Render as an aligned table.
{
  printf 'HOST\tBATCH_ID\tDEPTH\tRATIO\tUTIL\tAMOUNT\tTTL_DAYS\tLABEL\n'
  echo "$result" | jq -r '
    .[] | [
      .host,
      .batchID,
      .depth,
      (.utilizationRatio // 0),
      .utilization,
      .amount,
      ((.batchTTL // 0) / 86400 | . * 10 | round / 10),
      (.label // "")
    ] | @tsv'
} | column -t -s $'\t'

echo ""
echo "Matched $count batch(es) with depth > $MIN_DEPTH and utilizationRatio > $MIN_RATIO across ${#hosts[@]} nodes."
