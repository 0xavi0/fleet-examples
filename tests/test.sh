#!/usr/bin/env bash
set -e

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

    pushd "../$case"

    # shellcheck disable=SC2086
    fleet apply $ns_arg -o - test > "$outdir/bundle.yaml"

    # shellcheck disable=SC2086
    fleet target $ns_arg -b "$outdir/bundle.yaml" > "$outdir/target.yaml"

    split_and_deploy "$outdir/target.yaml" "$outdir"

    rm "$outdir/target.yaml"

    popd
}

for fixture in ./expected/single-cluster/*; do
    case="${fixture#./expected/}"
    run_fixture "$case"
done

for fixture in ./expected/multi-cluster/*; do
    case="${fixture#./expected/}"
    run_fixture "$case" "-n fleet-default"
done

diff -iwqr output expected

echo All is OK
rm -rf output
