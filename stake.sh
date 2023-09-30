set -x

list=( $(kubectl get ingress -n bee-storage | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    curl -XPOST $url/stake/100000000000000000 -s &
done