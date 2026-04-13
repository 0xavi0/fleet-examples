#!/usr/bin/env bash
set -euo pipefail

N=${1:?Usage: $0 <N> [<clusters-per-bundle>]}
T=${2:-2}   # number of downstream clusters targeted per bundle

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Detect yq flavour: mikefarah/yq (Go) vs kislyuk/yq (Python/jq-wrapper)
if yq --version 2>&1 | grep -qi "mikefarah"; then
  YQ_GO=true
else
  YQ_GO=false
fi

# yq_set_secret_data <value> <file>  — sets .secret.data in-place
yq_set_secret_data() {
  local val="$1" file="$2"
  if $YQ_GO; then
    yq e ".secret.data = ${val}" -i "${file}"
  else
    yq -y ".secret.data = ${val}" "${file}" > "${file}.tmp" && mv "${file}.tmp" "${file}"
  fi
}

# yq_to_json <file>  — prints the YAML file as compact JSON
yq_to_json() {
  local file="$1"
  if $YQ_GO; then
    yq e -o=json '.' "${file}" | jq -cS .
  else
    yq '.' "${file}" | jq -cS .
  fi
}

ITERATION=0
LAST_SUFFIX=""
LAST_COMMIT=""

while true; do
  ITERATION=$((ITERATION + 1))

  # Random R between 1 and N
  R=$(( (RANDOM % N) + 1 ))
  SUFFIX=$(printf "%03d" "$R")
  FOLDER="test-th-${SUFFIX}"
  VALUES_FILE="${FOLDER}/values_helm.yaml"

  echo "[Iter ${ITERATION}] Updating ${FOLDER} (secret.data = ${ITERATION})"

  # Add/update secret.data with the iteration number
  yq_set_secret_data "${ITERATION}" "${VALUES_FILE}"

  # Build expected JSON (sorted keys, compact) from the updated file
  EXPECTED_JSON=$(yq_to_json "${VALUES_FILE}")

  # Commit and push
  git add "${VALUES_FILE}"
  git commit -m "iteration ${ITERATION}: update ${FOLDER}"
  LAST_COMMIT=$(git rev-parse HEAD)
  LAST_SUFFIX="${SUFFIX}"

  git push origin helm-chart-deps

  echo "[Iter ${ITERATION}] Pushed commit ${LAST_COMMIT:0:7}, waiting for secret..."

  SECRET_NAME="test-th-${SUFFIX}-test-th-${SUFFIX}"
  MAX_WAIT=300
  ELAPSED=0
  VERIFIED=0
  NAMESPACES=""
  NS_COUNT=0

  while [ "${ELAPSED}" -lt "${MAX_WAIT}" ]; do
    # Find all namespaces containing this secret that match the expected prefix
    echo "[Debug] kubectl get secret --all-namespaces -o jsonpath=... | grep '${SECRET_NAME}'"
    NAMESPACES=$(kubectl get secret --all-namespaces \
      -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' 2>/dev/null \
      | grep " ${SECRET_NAME}$" \
      | grep "^cluster-fleet-default-sim-cluster-" \
      | awk '{print $1}' || true)
    echo "[Debug] NAMESPACES='${NAMESPACES}'"

    if [ -z "${NAMESPACES}" ]; then
      NS_COUNT=0
    else
      NS_COUNT=$(echo "${NAMESPACES}" | grep -c '.')
    fi
    echo "[Debug] NS_COUNT=${NS_COUNT} (expected ${T})"

    if [ "${NS_COUNT}" -gt "${T}" ]; then
      echo "ERROR at iteration ${ITERATION}: found ${NS_COUNT} secrets named '${SECRET_NAME}' in namespaces matching 'cluster-fleet-default-sim-cluster-*' (expected exactly ${T})"
      echo "Folder: ${FOLDER}"
      echo "Commit: ${LAST_COMMIT}"
      exit 1
    fi

    if [ "${NS_COUNT}" -eq "${T}" ]; then
      ALL_VERIFIED=1
      while IFS= read -r NS; do
        [ -z "${NS}" ] && continue
        echo "[Debug] kubectl get secret '${SECRET_NAME}' -n '${NS}' -o jsonpath='{.data.stagedValues}'"
        STAGED_RAW=$(kubectl get secret "${SECRET_NAME}" -n "${NS}" \
          -o jsonpath='{.data.stagedValues}' 2>/dev/null | base64 -d || true)
        echo "[Debug] kubectl get secret '${SECRET_NAME}' -n '${NS}' -o jsonpath='{.data.values}'"
        VALUES_RAW=$(kubectl get secret "${SECRET_NAME}" -n "${NS}" \
          -o jsonpath='{.data.values}' 2>/dev/null | base64 -d || true)
        echo "[Debug] NS='${NS}' STAGED_RAW='${STAGED_RAW}' VALUES_RAW='${VALUES_RAW}'"

        STAGED_JSON=$(echo "${STAGED_RAW}" | jq -cS . 2>/dev/null || true)
        VALUES_JSON=$(echo "${VALUES_RAW}" | jq -cS . 2>/dev/null || true)

        if [ "${STAGED_JSON}" != "${EXPECTED_JSON}" ] || [ "${VALUES_JSON}" != "${EXPECTED_JSON}" ]; then
          ALL_VERIFIED=0
          break
        fi
      done <<< "${NAMESPACES}"

      if [ "${ALL_VERIFIED}" -eq 1 ]; then
        echo "[Iter ${ITERATION}] Secret data verified in all ${T} namespace(s)!"
        VERIFIED=1
        break
      fi
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
  done

  if [ "${VERIFIED}" -eq 0 ]; then
    echo ""
    echo "ERROR at iteration ${ITERATION}: secret data mismatch or ${MAX_WAIT}s timeout reached"
    echo "  Folder:        ${FOLDER}"
    echo "  Commit:        ${LAST_COMMIT}"
    echo "  Expected JSON: ${EXPECTED_JSON}"
    if [ "${NS_COUNT}" -gt 0 ]; then
      echo "  Found ${NS_COUNT}/${T} namespace(s): $(echo "${NAMESPACES}" | tr '\n' ' ')"
      while IFS= read -r NS; do
        [ -z "${NS}" ] && continue
        STAGED_RAW=$(kubectl get secret "${SECRET_NAME}" -n "${NS}" \
          -o jsonpath='{.data.stagedValues}' 2>/dev/null | base64 -d || true)
        VALUES_RAW=$(kubectl get secret "${SECRET_NAME}" -n "${NS}" \
          -o jsonpath='{.data.values}' 2>/dev/null | base64 -d || true)
        STAGED_JSON=$(echo "${STAGED_RAW}" | jq -cS . 2>/dev/null || true)
        VALUES_JSON=$(echo "${VALUES_RAW}" | jq -cS . 2>/dev/null || true)
        echo "  [${NS}] stagedValues: ${STAGED_JSON:-<empty or invalid JSON>}"
        echo "  [${NS}] values:       ${VALUES_JSON:-<empty or invalid JSON>}"
      done <<< "${NAMESPACES}"
    else
      echo "  Secret '${SECRET_NAME}' not found in any namespace matching 'cluster-fleet-default-sim-cluster-*'"
    fi
    exit 1
  fi
done
