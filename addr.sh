list=($(kubectl get ingress -n bee-light-testnet | grep testnet.internal | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    echo $url && curl -s $url/addresses | jq -c .ethereum  | tr -d '"'
done
