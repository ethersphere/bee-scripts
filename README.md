# bee-scripts

Scripts and small Go programs used by the Bee team to debug and operate Swarm testnet and mainnet nodes.

Most shell scripts target Bee nodes running in a Kubernetes namespace and discover hosts via `kubectl get ingress`. They typically accept `NAMESPACE` and `DOMAIN` as the first arguments.

Some scripts have a `*-pf.sh` variant that reaches nodes via `kubectl port-forward` instead of ingress (useful when no ingress is exposed). These open a local forward to one node at a time, run the request, then close it and wait for the local port to free before the next node. The shared open/close-and-wait logic lives in [`scripts/lib/portforward.sh`](scripts/lib/portforward.sh); the `*-pf.sh` scripts take `[NAMESPACE] [LOCAL_PORT] [API_PORT]` (defaults `11633` / `1633`) in place of a domain.

## Layout

- [`scripts/`](scripts) — Bash utilities (see categories below)
- [`neighborhood/`](neighborhood) — compute neighborhood population from a Swarmscan dump
- [`readsi/`](readsi) — human-readable breakdown of storage incentives (redistribution, stake, postage, reward)
- [`private-key/`](private-key) — print a node's swarm/ethereum private key from its data dir
- [`sharky-bits/`](sharky-bits) — inspect sharky `free_*` slot files
- [`testnet-update/`](testnet-update) — roll testnet nodes to a new RC version

## Requirements

`kubectl`, `curl`, `jq`, `bc` (plus `lsof` for the `*-pf.sh` port-forward variants), and Go 1.21+ for the programs under `neighborhood/`, `readsi/`, `private-key/`, `sharky-bits/`.

## Scripts overview

Run any script without args to see defaults; most accept `[NAMESPACE] [DOMAIN]`.

### Node info & health

- `addr.sh`, `addr-full.sh` — overlay/ethereum addresses per node (`addr-pf.sh` for the port-forward variant)
- `status.sh`, `status-peers.sh`, `bad-status.sh` — `/status` snapshot and peer counts
- `reachable.sh` — checks `isReachable`
- `overlay.sh`, `topology.sh`, `neighborhoods.sh` — overlay, topology, neighborhood depth
- `blocklist.sh`, `check-peers-overlay.sh` — peer/overlay lookups
- `wallet-get.sh` — wallet balances per node (`wallet-get-pf.sh` for the port-forward variant)
- `pending_transactions.sh`

### Chequebook & funds

- `chequebook-balance-get.sh` — flags nodes below the 11 BZZ threshold (`chequebook-balance-get-pf.sh` for the port-forward variant)
- `chequebook-deposit.sh` — deposit a fixed amount, or `--topup-to` a target balance (`chequebook-deposit-pf.sh` for the port-forward variant)
- `chequebook-cashout-withdraw.sh` — cash out cheques and withdraw before nuking
- `cashout.sh`, `deposit.sh`

### Stake

- `stake.sh`, `stake-get.sh` (`stake-get-pf.sh` for the port-forward variant), `stake-del.sh`

### Stamps & chunks

- `calculate_bzz.sh` — BZZ cost for a given depth and duration
- `convert.sh` — BZZ ⇄ PLUR conversion
- `dilute.sh`, `dilute-parallel.sh` — bump stamp depth
- `chunk-check.sh` — verify chunk presence across nodes
- `parallel_stamps_requests.sh`

### Cluster ops

- `collect-all.sh` — bundles status, overlay, and pod logs into `scripts/output/`
- `snapshot.sh` — pre-upgrade baseline (version, addresses, balances) for every node
- `pprof.sh` — fetch pprof profiles from a node's debug endpoint
- `testnet-update/testnet-update.sh` — roll bootnode/gateway/storage to a tagged RC
- `basefee.sh` — current Ethereum base fee from an RPC endpoint
- `secrets.sh`, `tag.sh` — bulk delete helm-release secrets / git tags
- `deltrx.sh` — cancel pending transactions
- `split.sh`, `rchash.sh`, `parallel_rpc_requests.sh`

## Maintainers

- [Bee](https://github.com/orgs/ethersphere/teams/bee) team
