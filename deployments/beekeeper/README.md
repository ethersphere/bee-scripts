# HELM

## Install Job

```bash
helm upgrade --install beekeeper-check-public ethersphere/beekeeper --namespace beekeeper -f ./beekeeper-check-public.yaml
```

## Uninstall Job

```bash
helm uninstall beekeeper-check-public --namespace beekeeper
```

## Start Job from scheduled cronjob

```bash
kubectl create job --from=cronjob/beekeeper-checks-cronjob beekeeper-check-immediate --namespace=beekeeper
```
