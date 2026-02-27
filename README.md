# Fleet Examples

This repository contains examples of how to use Fleet using different approaches.
The repo is broken up into two different sections: Single cluster and Multi Cluster.

[![CI](https://github.com/rancher/fleet-examples/actions/workflows/ci.yml/badge.svg)](https://github.com/rancher/fleet-examples/actions/workflows/ci.yml)

## Single Cluster Examples

All examples will deploy content to clusters with no per-cluster customizations. This is a good starting point to
understand the basics of structuring git repos for Fleet.

| Example | Description |
|-------------|-------------|
| [manifests](single-cluster/manifests/) | An example using raw Kubernetes YAML |
| [helm](single-cluster/helm/) | An example using Helm |
| [helm-multi-chart](single-cluster/helm-multi-chart/) | An example deploying multiple charts from a single repo |
| [kustomize](single-cluster/kustomize/) | An example using Kustomize |
| [helm-kustomize](single-cluster/helm-kustomize/) | An example using Kustomize to modify a third party Helm chart |

## Multi-Cluster Examples

The examples below will deploy a single git repo to multiple clusters at once
and configure the app differently for each target.

| Example | Description |
|-------------|-------------|
| [manifests](multi-cluster/manifests/) | A full example of using raw Kubernetes YAML and customizing it per target cluster |
| [helm](multi-cluster/helm/) | A full example of using Helm and customizing it per target cluster |
| [helm-external](multi-cluster/helm-external/) | A full example of using a Helm chart that is downloaded from a third party source and customizing it per target cluster |
| [kustomize](multi-cluster/kustomize/) | A full example of using Kustomize and customizing it per target cluster |
| [helm-kustomize](multi-cluster/helm-kustomize/) | A full example of using Kustomize to modify a third party Helm chart |
| [windows-helm](multi-cluster/windows-helm/) | A full example of using Helm for Windows cluster(s)

## Windows Example

Using downstream clusters with Windows nodes?
Check out the [windows-helm](multi-cluster/windows-helm/) multi-cluster example above.

## Running Tests Locally

The test suite renders every example using the Fleet CLI and compares the output
against committed expected files.

### Prerequisites

- [k3d](https://k3d.io/) v5.8.3 or newer
- `kubectl`
- Fleet CLI — download a release binary from
  [fleet releases](https://github.com/rancher/fleet/releases) and put it on
  your `PATH`, e.g.:
  ```bash
  FLEET_VERSION=v0.14.3
  curl -sL "https://github.com/rancher/fleet/releases/download/${FLEET_VERSION}/fleet-linux-amd64" \
    -o ~/.local/bin/fleet && chmod +x ~/.local/bin/fleet
  ```

### One-time cluster setup

Create a minimal k3d cluster, install Fleet CRDs, and populate the cluster
objects the tests rely on:

```bash
FLEET_VERSION=v0.14.3

# Create cluster
k3d cluster create fleet-test --no-lb --wait --timeout 120s
k3d kubeconfig merge fleet-test --kubeconfig-merge-default

# Install Fleet CRDs (use the same version as your fleet CLI)
curl -sL "https://github.com/rancher/fleet/releases/download/${FLEET_VERSION}/fleet-crd-${FLEET_VERSION#v}.tgz" \
  | tar -xz -O fleet-crd/templates/crds.yaml \
  | kubectl apply -f -

# Create namespaces and cluster objects
kubectl create namespace fleet-local
kubectl create namespace fleet-default
kubectl apply -f tests/setup-cluster.yaml
```

The cluster can be reused across test runs and deleted afterwards with
`k3d cluster delete fleet-test`.

### Running the tests

```bash
tests/test.sh
```

The script runs `fleet apply`, `fleet target`, and `fleet deploy -d` for each
example and compares the rendered output against the files in `tests/expected/`.

### Updating expected files

When an example or the Fleet CLI changes the rendered output, regenerate the
expected files by running the tests once until they fail on the `diff` step,
then copy the fresh output into `expected/`:

```bash
# Run once — will fail at the diff step but generate the new output
tests/test.sh || true

# Accept the new output as the expected baseline
cp -r tests/output/* tests/expected/
# or selectively: cp tests/output/multi-cluster/kustomize/dev-output.yaml \
#                    tests/expected/multi-cluster/kustomize/dev-output.yaml
```
