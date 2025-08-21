# Single Helm chart shared between 3 Bundles example

This example deploys the same Helm chart in 3 different Bundles with their own Helm values.
It also demonstrates how to use [user-driven scan](https://fleet.rancher.io/next/explanations/gitrepo-content#_alternative_scan_explicitly_defined_by_the_user).

```yaml
kind: GitRepo
apiVersion: fleet.cattle.io/v1alpha1
metadata:
  name: test-helm-overlays
  namespace: fleet-local
spec:
  repo: https://github.com/rancher/fleet-examples
  bundles:
    - base: single-cluster/helm-overlays
      options: overlays/development/fleet.yaml
    - base: single-cluster/helm-overlays
      options: overlays/test/test.yaml
    - base: single-cluster/helm-overlays
      options: overlays/production/prod.yaml
```
