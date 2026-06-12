#!/bin/bash

# portforward.sh — sourceable helper for one-at-a-time `kubectl port-forward` access.
#
# Opens a local forward to a single Bee node, lets you run a request against it, then
# tears the forward down and BLOCKS until the local port is actually released — so the
# same local port can be reused for the next node without "address already in use".
#
# Requires: kubectl, curl, lsof.
#
# Quick use (open + request + close, one call per node):
#   source "$(dirname "$0")/lib/portforward.sh"
#   body=$(pf_query "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" "/wallet") || echo "failed"
#
# Manual use (multiple requests while the forward is up):
#   pf_open "$NAMESPACE" "$pod" "$LOCAL_PORT" "$API_PORT" || { echo "open failed"; pf_close; }
#   a=$(curl -s "http://localhost:$LOCAL_PORT/wallet")
#   b=$(curl -s "http://localhost:$LOCAL_PORT/addresses")
#   pf_close
#
# Node discovery (pf_list_nodes):
#   pods=($(pf_list_nodes "$NAMESPACE"))
# Selects bee pods by label (works for any pod naming — bee-0 or bee-base-1-0) and drops
# bootnodes. Override the selector/exclusion for non-standard setups.
#
# Tunables (override before/after sourcing):
#   PF_POD_SELECTOR  kubectl label selector for bee nodes (default app.kubernetes.io/name=bee)
#   PF_POD_EXCLUDE   egrep pattern of pod names to drop (default bootnode; "" keeps all)
#   PF_HEALTH_PATH   readiness probe path (default /health)
#   PF_READY_TRIES   readiness poll attempts, 0.2s apart (default 50 = ~10s)
#   PF_FREE_TRIES    port-release poll attempts, 0.2s apart (default 50 = ~10s)

PF_POD_SELECTOR=${PF_POD_SELECTOR:-app.kubernetes.io/name=bee}
PF_POD_EXCLUDE=${PF_POD_EXCLUDE:-bootnode}
PF_HEALTH_PATH=${PF_HEALTH_PATH:-/health}
PF_READY_TRIES=${PF_READY_TRIES:-50}
PF_FREE_TRIES=${PF_FREE_TRIES:-50}

# pf_list_nodes <namespace> — print one bee pod name per line (bootnodes excluded).
pf_list_nodes() {
  local namespace=$1 out
  out=$(kubectl get pods -n "$namespace" -l "$PF_POD_SELECTOR" \
        --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
  [[ -n "$PF_POD_EXCLUDE" ]] && out=$(echo "$out" | grep -Ev "$PF_POD_EXCLUDE")
  echo "$out" | grep -v '^[[:space:]]*$'
}

# Internal state.
PF_PID=""
PF_LOCAL_PORT=""
PF_ABORT=0

# pf_aborted -> success (0) once a cancellation signal (Ctrl-C / TERM) has been received.
# Loops should check this and `break` so the whole run stops, not just one iteration:
#   for pod in "${pods[@]}"; do pf_aborted && break; ...; done
pf_aborted() { [[ "$PF_ABORT" == "1" ]]; }

# Signal handler for INT/TERM. Records the cancellation so loops stop before the next node
# and the in-flight wait loops bail promptly; the active forward is torn down by the EXIT
# trap (or the next pf_close). A second interrupt forces an immediate exit.
pf_on_cancel() {
  if pf_aborted; then
    echo "pf: second interrupt — exiting now." >&2
    exit 130
  fi
  PF_ABORT=1
  echo "" >&2
  echo "pf: cancellation requested — stopping after the current node (Ctrl-C again to force quit)." >&2
}

# pf_port_in_use <port> -> 0 if something is LISTENing on the port, 1 otherwise.
pf_port_in_use() {
  lsof -iTCP:"$1" -sTCP:LISTEN -n -P >/dev/null 2>&1
}

# pf_close — kill the active forward (if any) and block until its local port is free.
# Safe to call repeatedly and with no active forward. Used directly as the EXIT trap.
pf_close() {
  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" 2>/dev/null; then
    kill "$PF_PID" 2>/dev/null
    wait "$PF_PID" 2>/dev/null
  fi
  PF_PID=""

  [[ -z "$PF_LOCAL_PORT" ]] && return 0
  local tries=0
  while pf_port_in_use "$PF_LOCAL_PORT"; do
    pf_aborted && break   # don't block on port-release while cancelling
    sleep 0.2
    ((tries++))
    if ((tries > PF_FREE_TRIES)); then
      echo "pf: warning: port $PF_LOCAL_PORT still in use after wait; continuing" >&2
      break
    fi
  done
  PF_LOCAL_PORT=""
}

# pf_open <namespace> <pod> <local_port> <api_port>
# Start a forward and wait until it actually serves traffic. Returns 1 on failure.
pf_open() {
  local namespace=$1 pod=$2 local_port=$3 api_port=$4

  pf_aborted && return 1   # don't start new forwards once cancelling

  if pf_port_in_use "$local_port"; then
    echo "pf: error: local port $local_port already in use before forwarding to $pod" >&2
    return 1
  fi

  kubectl port-forward -n "$namespace" "pod/$pod" "$local_port:$api_port" >/dev/null 2>&1 &
  PF_PID=$!
  PF_LOCAL_PORT=$local_port

  local tries=0
  until curl -s -o /dev/null --max-time 2 "http://localhost:$local_port$PF_HEALTH_PATH"; do
    pf_aborted && return 1                       # stop waiting if cancelling
    # Bail if the forward process died (pod not ready, wrong port, etc.).
    kill -0 "$PF_PID" 2>/dev/null || return 1
    sleep 0.2
    ((tries++))
    ((tries > PF_READY_TRIES)) && return 1
  done
  return 0
}

# pf_query <namespace> <pod> <local_port> <api_port> <path>
# Open, GET <path>, close (always). Echoes the response body to stdout.
# Returns non-zero if the forward could not be established or curl failed.
pf_query() {
  local namespace=$1 pod=$2 local_port=$3 api_port=$4 path=$5

  if ! pf_open "$namespace" "$pod" "$local_port" "$api_port"; then
    pf_close
    return 1
  fi

  local body status
  body=$(curl -s --max-time 10 "http://localhost:$local_port$path")
  status=$?

  pf_close

  printf '%s' "$body"
  return $status
}

# Guarantee no dangling forward survives the sourcing script (error, normal exit, or a
# forced second Ctrl-C). INT/TERM record the cancellation (pf_on_cancel) so loops stop
# cleanly via pf_aborted, while the active forward is still torn down on the way out.
trap pf_close EXIT
trap pf_on_cancel INT TERM
