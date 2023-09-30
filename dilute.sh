set -x

declare -x cluster=${cluster:-"bee-gateway"}
declare -x start=${start:-0}
declare -x end=${end:-9}

for i in $(seq $start $end); 
do
    stampurl=http://bee-$i-0-debug.bee-gateway.mainnet.internal/stamps
    # stampurl=http://bee-0-0-debug.testnet-gateway.testnet.internal/stamps
    diluteDepth=34

    list=( $(curl $stampurl | jq  -c '.stamps[] | select(.exists) | .batchID' |  tr '\n' ' ' | tr -d '"' ) )

    for j in ${!list[@]};
    do
        item=${list[$j]}
        curl -X PATCH $stampurl/dilute/$item/${diluteDepth}
    done
done