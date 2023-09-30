# set -x

declare -x cluster=${cluster:-"private-localstorev2"}
declare -x anchor=${anchor1:-"aa"}
declare -x depth=${depth:-1}

function rchash {
    curl -s $1 | jq .Hash
    echo $1
}

nodes=( $(kubectl get ingress -n $cluster | grep -v debug | awk '{print $3}') )

for i in ${!nodes[@]};
do
    node=${nodes[$i]}
    url=$node/rchash/$depth/$anchor

    rchash $url &
done
