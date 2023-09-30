#!/usr/bin/env bash
[ -z ${DEBUG_API+x} ] && DEBUG_API=http://localhost:1635	
[ -z ${MIN_AMOUNT+x} ] && MIN_AMOUNT=10000000000000000	

set -x
# cashout script for bee >= 0.6.0
# note this is a simple bash script which might not work well or at all on some platforms
# for a more robust interface take a look at https://github.com/ethersphere/swarm-cli

function getPeers() {	
  curl -s "$DEBUG_API/chequebook/cheque" | jq -r '.lastcheques | .[].peer'	
}

function getUncashedAmount() {  
  curl -s "$DEBUG_API/chequebook/cashout/$1" | jq '.uncashedAmount' | tr -d '"' 
}

function cashout() {
  local peer=$1
  txHash=$(curl -s -XPOST "$DEBUG_API/chequebook/cashout/$peer" | jq -r .transactionHash)
  echo cashing out cheque for $peer in transaction $txHash >&2
}

function cashoutAll() {
  local minAmount=$1
  for peer in $(getPeers)
  do
    local uncashedAmount=$(getUncashedAmount $peer)
    if (( "$uncashedAmount" > $minAmount ))
    then
      echo "uncashed cheque for $peer ($uncashedAmount uncashed)" >&2
      cashout $peer
    fi
  done
}

function listAllUncashed() {
  for peer in $(getPeers)
  do
    local uncashedAmount=$(getUncashedAmount $peer)
    if (( "$uncashedAmount" > 0 ))
    then
      echo $peer $uncashedAmount
    fi
  done
}

case $1 in
cashout)
  cashout $2
  ;;
cashout-all)
  cashoutAll $MIN_AMOUNT
  ;;
uncashed-for-peer)
  getUncashedAmount $2
  ;;
list-uncashed|*)
  listAllUncashed
  ;;
esac