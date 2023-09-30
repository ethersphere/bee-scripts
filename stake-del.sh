set -x

list=( $(kubectl get ingress -n testnet-bootnode | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    curl -XDELETE $url/stake -s &
done