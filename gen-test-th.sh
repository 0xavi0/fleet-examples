#!/usr/bin/env bash
set -euo pipefail

N=${1:?Usage: $0 <number-of-folders> <number-of-clusters>}
C=${2:?Usage: $0 <number-of-folders> <number-of-clusters>}

for i in $(seq 1 "$N"); do
  num=$(printf "%03d" "$i")
  dir="test-th-${num}"
  cluster_num1=$(( (RANDOM % C) + 1 ))
  cluster_num2=$(( (RANDOM % C) + 1 ))
  while [ "$C" -gt 1 ] && [ "$cluster_num2" -eq "$cluster_num1" ]; do
    cluster_num2=$(( (RANDOM % C) + 1 ))
  done

  mkdir -p "$dir"

  cat > "$dir/values_helm.yaml" <<EOF
secret:
  name: test-secret-file-${num}
configmap-chart:
  configmap:
    name: test-cm-file-${num}
EOF

  cat > "$dir/fleet.yaml" <<EOF
defaultNamespace: test-th-${num}
helm:
  repo: https://github.com/0xavi0/fleet-examples/raw/refs/heads/helm-chart-deps/charts
  chart: secret-chart
  version: 0.2.0
  values:
    secret:
      name: test-secret-${num}
    configmap-chart:
      configmap:
        name: test-cm-${num}
targetCustomizations:
  - name: test
    clusterSelector:
      matchExpressions:
        - key: fleet.cattle.io/state
          operator: In
          values:
            - running
            - scaledDown
        - key: fleet.cattle.io/cluster
          operator: In
          values:
            - sim-cluster-${cluster_num1}
            - sim-cluster-${cluster_num2}
    helm:
      valuesFiles:
        - values_helm.yaml
      values:
        secret:
          name: test-secret-${num}
        configmap-chart:
          configmap:
            name: test-cm-${num}
  - clusterSelector:
      matchExpressions:
        - key: fleet.cattle.io/cluster
          operator: NotIn
          values:
            - sim-cluster-${cluster_num1}
            - sim-cluster-${cluster_num2}
    doNotDeploy: true
EOF

  echo "Created $dir"
done
