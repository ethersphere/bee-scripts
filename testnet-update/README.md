## Testnet update

Update the testnet with to the specified RC version.

Usage:
```
[PARALLEL_UPDATE=true] ./testnet-update.sh <namespace> <tag> [pod]
```
- namespace: `bootnode`, `gateway`, `storage`, `all`
- tag: must be a valid tag with `-rc[0-9]` suffix
- pod: optional pod name to update, only valid for a single namespace

Example:
- update all nodes in namespace `bootnode` to version `1.18.0-rc1`
```
./testnet-update.sh bootnode 1.18.0-rc1
```
- update a single node `bee-0` in namespace `bootnode` to version `1.18.0-rc1`
```
./testnet-update.sh bootnode 1.18.0-rc1 bee-0
```
- update all nodes in namespace `storage` to version `1.18.0-rc1` in parallel
```
PARALLEL_UPDATE=true ./testnet-update.sh storage 1.18.0-rc1
```

### Usual workflow
Connect to the testnet `VPN``, set kube `context` to the `halloween` cluster and execute the following commands:
```
./testnet-update.sh bootnode $VERSION
./testnet-update.sh gateway $VERSION
PARALLEL_UPDATE=true ./testnet-update.sh storage $VERSION
```

### Troubleshooting
If the update fails, error events will be printed in the output.
Check the logs of the pod with `kubectl logs -n <namespace> -f <pod>` and the events with `kubectl describe pod -n <namespace> <pod>`.
