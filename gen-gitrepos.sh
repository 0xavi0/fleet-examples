#!/bin/bash

set -e

N=${1:?Usage: $0 <number_of_gitrepos>}
OUTPUT_DIR="th-gitrepos"

mkdir -p "$OUTPUT_DIR"

for i in $(seq 1 "$N"); do
  NAME=$(printf "test-th-%03d" "$i")
  cat > "$OUTPUT_DIR/${NAME}.yaml" <<EOF
kind: GitRepo
apiVersion: fleet.cattle.io/v1alpha1
metadata:
  name: ${NAME}
  namespace: fleet-default
spec:
  repo: https://github.com/0xavi0/fleet-examples
  branch: helm-chart-deps
  disablePolling: true
  paths:
  - ${NAME}
  targets:
  # Match everything
  - clusterSelector: {}
EOF
done

echo "Generated $N GitRepo manifests in $OUTPUT_DIR/"
