# set -x

declare -x cluster=${cluster:-"testnet-gateway"}
declare -x start=${start:-0}
declare -x end=${end:-4}
declare -x diluteDepth=${diluteDepth:-34}

function dilute {

    stampurl=$1

    list=( $(curl -s $stampurl | jq  -c '.stamps[] | .batchID' |  tr '\n' ' ' | tr -d '"' ) )

    for i in ${!list[@]};
    do
        item=${list[$i]}
        curl -X PATCH $stampurl/dilute/$item/${diluteDepth}
    done
}

nodes=( $(kubectl get ingress -n $cluster | grep debug | awk '{print $3}') )

for i in ${!nodes[@]};
do
    node=${nodes[$i]}
    stampurl=$node/stamps
    # dilute $stampurl &
    # curl  $url/stake -s

    if (( $i < 30 )); then
        echo $stampurl
        dilute $stampurl &
    fi
done

# for i in $(seq $start $end);
# do
#     stampurl=http://bee-$i-0-debug.$cluster.testnet.internal/stamps
#     dilute $stampurl &
# done

# set -x

# declare -x cluster=${cluster:-"bee-gateway"}
# declare -x start=${start:-0}
# declare -x end=${end:-9}
# declare -x diluteDepth=${diluteDepth:-34}

# function dilute {

#     stampurl=$1

#     list=( $(curl $stampurl | jq  -c '.stamps[] | .batchID' |  tr '\n' ' ' | tr -d '"' ) )

#     for i in ${!list[@]};
#     do
#         item=${list[$i]}
#         curl -X PATCH $stampurl/dilute/$item/${diluteDepth}
#     done
# }

# for i in $(seq $start $end);
# do
#     stampurl=http://bee-$i-0-debug.$cluster.mainnet.internal/stamps
#     dilute $stampurl &
# done