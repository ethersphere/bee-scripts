for i in {0..19}
do
    echo $i
    curl http://bee-$i-0-debug.testnet-storage.testnet.internal/topology | jq 'del(.bins[]["connectedPeers", "disconnectedPeers"], .lightNodes)' | tee ./$i-topology.txt
done
