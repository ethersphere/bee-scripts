list=( $(kubectl get ingress -n testnet-storage | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    echo "bee-$i" && curl -s $url/addresses | jq -c .ethereum  | tr -d '"'
done