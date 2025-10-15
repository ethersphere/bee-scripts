set -x

cluster=$1

for i in {0..9};
do
    curl -s http://bee-$i-0-debug.$cluster.mainnet.internal/debug/pprof/profile -o tmp-$cluster-pprof-$i-$(date +%T-%m-%d-%Y) &
done;

sleep 40
tar -czf $cluster-pprof.tar.gz tmp-$cluster-pprof-*
mv $cluster-pprof.tar.gz $cluster-pprof-$(date +%T-%m-%d-%Y).tar.gz
rm tmp-$cluster-pprof-*