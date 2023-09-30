list=( $(kubectl get ingress -n bee-storage | grep debug | awk '{print $3}') )

for i in ${!list[@]};
do
    url=${list[$i]}
    curl $url/stake -s
done