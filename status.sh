list=( $(kubectl get ingress -n $1 | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    result=$(curl $url/status/peers -s) 
    # peers=( $(echo $result | jq -c '.snapshots[]') )
    peers=( $(echo $result | jq -c '.snapshots[]') )
    for j in ${!peers[@]};
    do
        peer=${peers[$j]}
        echo $peer >> status.json
        echo $url >> status.json
    done
done


# ./scripts/status.sh bee-gateway && ./scripts/status.sh bee-storage && ./scripts/status.sh dev-bee-gateway && ./scripts/status.sh dev-bee-storage && ./scripts/status.sh bee-bootnode && ./scripts/status.sh dev-bee-bootnode
