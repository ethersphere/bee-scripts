list=( $(kubectl get ingress -n $1 | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    result=$(curl $url/status/peers -s) 
    peers=( $(echo $result | jq -c '.snapshots[]') )
    # peers=( $(echo $result | jq -c '.snapshots[] | select(.storageRadius != 9 or .neighborhoodSize < 1 ) ') )
    for j in ${!peers[@]};
    do
        peer=${peers[$j]}
        echo $peer >> bad-peers.json
        # echo $url >> bad-peers.json
        # overlay=$(echo $peer | jq -c '.peer' | tr -d '"')
        # curl -s https://api.swarmscan.io/v1/network/nodes/$overlay | jq '.location.country' >> bad-peers.json
    done
done


# ./scripts/bad-status.sh bee-gateway && ./scripts/bad-status.sh bee-storage && ./scripts/bad-status.sh dev-bee-gateway && ./scripts/bad-status.sh dev-bee-storage && ./scripts/bad-status.sh bee-bootnode && ./scripts/bad-status.sh dev-bee-bootnode
