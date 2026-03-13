#!/usr/bin/env bash
set -euo pipefail

# Ensure yq is available for YAML normalization
if ! command -v yq &>/dev/null; then
    echo "❌ Error: yq is required but not found in PATH"
    exit 1
fi

export COMMIT=fake

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

rm -rf output

# split_and_deploy TARGET_YAML OUTDIR
#   Splits `fleet target` YAML output by document and runs `fleet deploy -d`
#   for each BundleDeployment, writing <cluster>-output.yaml files.
split_and_deploy() {
    local target_yaml="$1" outdir="$2" content="" cluster tmpfile
    while IFS= read -r -d $'\0' doc; do
        if grep -q "^kind: Content" <<< "$doc"; then
            content="$doc"
        elif grep -q "^kind: BundleDeployment" <<< "$doc"; then
            cluster=$(grep 'fleet\.cattle\.io/cluster:' <<< "$doc" | grep -v namespace | sed -E 's/.*: "?([^"]+)"?/\1/' | head -1)
            [[ -z "$cluster" ]] && continue
            tmpfile=$(mktemp)
            printf -- "---\n%s\n---\n%s\n" "$content" "$doc" > "$tmpfile"
            fleet deploy -d -i "$tmpfile" > "$outdir/${cluster}-output.yaml"
            rm "$tmpfile"
        fi
    done < <(awk 'BEGIN{RS="---\n"; ORS="\0"} NF' "$target_yaml")
}

# normalize_yaml FILE: sort list items by kind and name for comparison
normalize_yaml() {
    yq 'sort_by(.kind, .metadata.name)' "$1"
}

fleet -v

# run_fixture CASE [NS_ARG]
#   - Generates bundle.yaml via `fleet apply`
#   - Runs `fleet target` to resolve per-cluster BundleDeployments
#   - Calls split_and_deploy which runs `fleet deploy -d` per cluster,
#     writing <cluster>-output.yaml files
run_fixture() {
    local case="$1"
    local ns_arg="${2:-}"
    local outdir="$SCRIPT_DIR/output/$case"
    mkdir -p "$outdir"

    pushd "../$case" > /dev/null

    # shellcheck disable=SC2086
    fleet apply $ns_arg -o - test > "$outdir/bundle.yaml"

    # shellcheck disable=SC2086
    fleet target $ns_arg -b "$outdir/bundle.yaml" > "$outdir/target.yaml"

    split_and_deploy "$outdir/target.yaml" "$outdir"

    rm "$outdir/target.yaml"

    popd > /dev/null
}

for fixture in ./expected/single-cluster/*; do
    case="${fixture#./expected/}"
    run_fixture "$case"
done

for fixture in ./expected/multi-cluster/*; do
    case="${fixture#./expected/}"
    run_fixture "$case" "-n fleet-default"
done

# Compare output files, ignoring resource ordering
test_failed=0
shopt -s nullglob
for expected_file in expected/*/*; do
    [[ ! -f "$expected_file" ]] && continue

    output_file="output/${expected_file#expected/}"

    if [[ ! -f "$output_file" ]]; then
        echo "❌ Missing: $output_file"
        test_failed=1
        continue
    fi

    # Normalize and compare
    expected_norm=$(normalize_yaml "$expected_file")
    output_norm=$(normalize_yaml "$output_file")

    if ! diff -q <(echo "$expected_norm") <(echo "$output_norm") > /dev/null 2>&1; then
        if [[ $test_failed -eq 0 ]]; then
            echo "❌ Test failed: output differs from expected (ignoring resource order)"
            echo ""
            echo "=== DIFFERENCES (normalized) ==="
        fi
        echo "File: $expected_file"
        diff -u <(echo "$expected_norm" | head -30) <(echo "$output_norm" | head -30) || true
        test_failed=1
    fi
done

if [[ $test_failed -eq 1 ]]; then
    exit 1
fi

echo All is OK
rm -rf output

