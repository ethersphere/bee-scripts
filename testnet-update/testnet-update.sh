#!/usr/bin/env bash

set -eo pipefail
# set -x
#/
#/ Usage:
#/ ./testnet-update.sh <namespace> <tag> [pod]
#/
#/ Description:
#/ Update bee testnet to the specified rc version
#/
#/ Example:
#/ ./testnet-update.sh bootnode 1.18.0-rc1
#/
#/ ./testnet-update.sh bootnode 1.18.0-rc1 bee-0
#/
#/ Update all specified nodes in parallel
#/ PARALLEL_UPDATE=true ./testnet-update.sh storage 1.18.0-rc1
#/
#/ Use different image repository
#/ IMAGE=personal-repo/bee-testnet ./testnet-update.sh storage 1.18.0-rc1
#/
#/ Namespaces: bootnode, gateway, storage, all
#/
#/ Tag: must be a valid tag with -rc[0-9] suffix
#/
#/ Pod: optional pod name to update, only valid for a single namespace
#/

# parse file and print usage text
usage() { grep '^#/' "$0" | cut -c4- ; exit 0 ; }
expr "$*" : ".*-h" > /dev/null && usage
expr "$*" : ".*--help" > /dev/null && usage

declare -x NAMESPACES="bootnode gateway storage"
declare -x namespaces="testnet-bootnode testnet-gateway testnet-storage"

declare -x IMAGE=${IMAGE:-ethersphere/bee}

if ! command -v jq &> /dev/null; then
    echo "jq is missing..."
    exit 1
elif ! command -v kubectl &> /dev/null; then
    echo "kubectl is missing..."
    exit 1
fi

read -r USERNAME CLUSTER <<< "$(kubectl config view --minify -o json | jq -r '.users[0].name  + " " + .clusters[0].name')"

update () {
  _namespace=$1
  _tag=$2
  _sts=$3
  if ! kubectl annotate -n "${_namespace}" sts "${_sts}" kubernetes.io/change-cause="${USERNAME} updated to ${_tag}"; then
    echo "Failed to annotate pod ${_sts}"
    exit 1
  fi
  if ! kubectl set image -n "${_namespace}" sts "${_sts}" bee="${IMAGE}":"${_tag}"; then
    echo "Failed to update pod ${_sts}"
    exit 1
  fi
  kubectl rollout status -n "${_namespace}" -w sts "${_sts}" &
  pid_rollout=$!
  kubectl get events -n "${_namespace}" --field-selector involvedObject.name="${_sts}"-0,type!=Normal,reason!=FailedAttachVolume,reason!=FailedKillPod --no-headers=true --watch-only &
  pid_events=$!
  wait $pid_rollout
  kill $pid_events
  echo "Updated ${_sts} to $_tag in namespace ${_namespace}"
}

# check if namespace is valid
if [[ " ${NAMESPACES[*]} " =~ ${1} ]]; then
  namespaces=testnet-"${1}"
elif [[ "all" == "${1}" ]]; then
  if [[ -n "${3}" ]]; then
    echo "Pod can only be specified for a single namespace"
    exit 1
  fi
else
  echo "Invalid namespace: ${1}"
  exit 1
fi

# check if tag is valid
if ! [[ ${2} =~ ^[0-9]+\.[0-9]+\.[0-9]+-rc[0-9]+$ ]]; then
  echo "Invalid tag: ${2}"
  exit 1
fi

# check if pod is valid
if [[ -n "${3}" ]]; then
  if ! [[ ${3} =~ ^bee-[0-9]+$ ]]; then
    echo "Invalid pod: ${3}"
    exit 1
  fi
  if ! kubectl get sts -n "${namespaces}" "${3}" > /dev/null 2>&1; then
    echo "Invalid pod: ${3}"
    exit 1
  fi
fi

if [[ "${CLUSTER}" != "halloween" ]]; then
  echo "Current cluster: ${CLUSTER}"
  echo "Cluster must be halloween!"
  exit 1
fi

# update pods
for ns in ${namespaces}; do
  if [[ -n "${3}" ]]; then
    update "${ns}" "${2}" "${3}"
  else
    for sts in $(kubectl get sts -n "${ns}"  -l app.kubernetes.io/name=bee -o json | jq -r '.items[].metadata.name'); do
      if [[ -n "${PARALLEL_UPDATE}" ]]; then
        update "${ns}" "${2}" "${sts}" &
      else
        update "${ns}" "${2}" "${sts}"
      fi
    done
    if [[ -n "${PARALLEL_UPDATE}" ]]; then
      wait
    fi
  fi
done
