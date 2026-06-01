#!/bin/bash

# This script compares the /batches and /chainstate endpoint responses of two Bee nodes
# (or two ports on the same host) and prints a unified diff of the normalized JSON for each.
# It requires 'curl', 'jq', and 'diff' to be installed on the system.
# Usage: ./batches-diff.sh [URL_A] [URL_B] [TTL_TOLERANCE]
# Example: ./batches-diff.sh http://localhost:1633 http://localhost:1635 5

# Base URLs to compare, default to the two local endpoints
URL_A=${1:-http://localhost:1633}
URL_B=${2:-http://localhost:1635}

# Allowed batchTTL drift (in seconds) before it counts as a difference.
# batchTTL is time-dependent, so the two nodes are rarely sampled at the exact same instant.
TTL_TOLERANCE=${3:-5}

# Endpoints to compare
ENDPOINTS=(/batches /chainstate)

# Fetch and normalize a JSON endpoint response.
# For /batches we unwrap the {"batches": [...]} envelope and sort the array by batchID so
# ordering differences don't show up as diffs. jq -S sorts object keys for a stable layout.
# batchTTL is kept here and handled separately with a tolerance.
fetch() {
  local base="$1" path="$2" body
  body=$(curl -s -f "${base}${path}")
  if [ $? -ne 0 ] || [ -z "$body" ]; then
    echo "Error: failed to fetch ${base}${path}" >&2
    return 1
  fi
  echo "$body" | jq -S '(.batches // .) | if type == "array" then sort_by(.batchID) else . end'
}

# Compare a single endpoint across the two URLs. Returns 1 if they differ.
compare_endpoint() {
  local path="$1"
  echo "Comparing ${URL_A}${path} <-> ${URL_B}${path}"
  echo "=========================================================="

  local tmp_a tmp_b
  tmp_a=$(mktemp)
  tmp_b=$(mktemp)

  if ! fetch "$URL_A" "$path" > "$tmp_a" || ! fetch "$URL_B" "$path" > "$tmp_b"; then
    rm -f "$tmp_a" "$tmp_b"
    return 1
  fi

  local rc=0
  local diff_a="$tmp_a" diff_b="$tmp_b"

  # /batches-specific checks: batch count, batchTTL tolerance, and a batchTTL-stripped diff.
  if [ "$path" = "/batches" ]; then
    local count_a count_b
    count_a=$(jq 'if type == "array" then length else 0 end' "$tmp_a")
    count_b=$(jq 'if type == "array" then length else 0 end' "$tmp_b")
    if [ "$count_a" = "$count_b" ]; then
      echo "✅ batch count matches: $count_a"
    else
      echo "❌ batch count differs: ${URL_A}=${count_a} vs ${URL_B}=${count_b}"
      rc=1
    fi

    # batchTTL: match batches by batchID and flag any whose TTL drifts beyond the tolerance.
    local ttl_out
    ttl_out=$(jq -rn --argjson tol "$TTL_TOLERANCE" \
      --slurpfile a "$tmp_a" --slurpfile b "$tmp_b" '
        ($b[0] | map({key: .batchID, value: .batchTTL}) | from_entries) as $bttl
        | $a[0]
        | map(select(.batchTTL != null and $bttl[.batchID] != null
                     and ((.batchTTL - $bttl[.batchID]) | fabs) > $tol)
              | {batchID, a: .batchTTL, b: $bttl[.batchID],
                 delta: (.batchTTL - $bttl[.batchID])})
        | .[] | "  \(.batchID): \(.a) vs \(.b) (Δ\(.delta))"')
    if [ -z "$ttl_out" ]; then
      echo "✅ batchTTL within tolerance (±${TTL_TOLERANCE}s)."
    else
      echo "❌ batchTTL drift beyond ±${TTL_TOLERANCE}s:"
      echo "$ttl_out"
      rc=1
    fi

    # Strip batchTTL before the structural diff so in-tolerance drift isn't reported twice.
    diff_a=$(mktemp)
    diff_b=$(mktemp)
    jq 'map(del(.batchTTL))' "$tmp_a" > "$diff_a"
    jq 'map(del(.batchTTL))' "$tmp_b" > "$diff_b"
  fi

  if diff -q "$diff_a" "$diff_b" >/dev/null; then
    echo "✅ ${path} responses are identical (batchTTL excluded)."
  else
    echo "❌ ${path} responses differ:"
    echo "----------------------------------------------------------"
    diff -u --label "${URL_A}${path}" --label "${URL_B}${path}" "$diff_a" "$diff_b"
    rc=1
  fi

  rm -f "$tmp_a" "$tmp_b"
  [ "$diff_a" != "$tmp_a" ] && rm -f "$diff_a" "$diff_b"
  echo ""
  return $rc
}

overall_rc=0
for path in "${ENDPOINTS[@]}"; do
  compare_endpoint "$path" || overall_rc=1
done

exit $overall_rc
