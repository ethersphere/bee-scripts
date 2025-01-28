# HELM

## Install Job

```bash
helm upgrade --install beekeeper-check-public ethersphere/beekeeper --namespace beekeeper -f ./beekeeper-check-public.yaml
```

## Uninstall Job

```bash
helm uninstall beekeeper-check-public --namespace beekeeper
```
