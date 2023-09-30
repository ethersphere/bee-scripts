list=( $(kubectl get ingress -n $1 | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    addr=$(curl $url/addresses -s | jq '.overlay')
    echo "$url $addr"
done
