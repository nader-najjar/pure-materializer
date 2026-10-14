#!/usr/bin/env bash
set -euo pipefail

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/admit-stage"
fixture_root=$(mktemp -d)
trap 'rm -rf "$fixture_root"' EXIT
mkdir "$fixture_root/bin"
export PATH="$fixture_root/bin:$PATH"
export GITHUB_REPOSITORY='nader-najjar/template-pure-pipeline'
export GITHUB_SHA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
export GH_TOKEN='test-token'
old_sha='1111111111111111111111111111111111111111'
new_sha='2222222222222222222222222222222222222222'

cat > "$fixture_root/bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == api ]]
printf '%s\n' "$*" >> "$ADMISSION_TEST_STATE/calls"
if [[ $* == *'/branches/main'* ]]; then
    [[ ! -e "$ADMISSION_TEST_STATE/branch-error" ]] || exit 1
    cat "$ADMISSION_TEST_STATE/main"
elif [[ $* == *'--method POST'* ]]; then
    request=$(cat)
    jq -e --arg ref "$GITHUB_SHA" '
        .ref == $ref and .task == "stage-admission" and .auto_merge == false and
        .required_contexts == [] and .production_environment == false
    ' <<< "$request" >/dev/null
    printf '%s\n' "$request" >> "$ADMISSION_TEST_STATE/requests"
    [[ ! -e "$ADMISSION_TEST_STATE/write-error" ]] || exit 1
    if [[ -e "$ADMISSION_TEST_STATE/non-created" ]]; then
        printf 'HTTP/2.0 202 Accepted\r\n\r\n'
        exit 0
    fi
    environment=$(jq -r '.environment' <<< "$request")
    records="$ADMISSION_TEST_STATE/$environment.json"
    [[ -e $records ]] || echo '[]' > "$records"
    jq --argjson request "$request" '. + [{task: $request.task, payload: $request.payload}]' \
        "$records" > "$records.tmp"
    mv "$records.tmp" "$records"
    if [[ -e "$ADMISSION_TEST_STATE/lost-response" ]]; then
        rm "$ADMISSION_TEST_STATE/lost-response"
        exit 1
    fi
    printf 'HTTP/2.0 201 Created\r\nContent-Type: application/json\r\n\r\n'
else
    [[ $* == *'--method GET'* && $* == *'--paginate'* && $* == *'--slurp'* && $* == *'per_page=100'* ]]
    [[ ! -e "$ADMISSION_TEST_STATE/read-error" ]] || exit 1
    environment=''
    for arg in "$@"; do
        if [[ $arg == environment=* ]]; then environment=${arg#environment=}; fi
    done
    [[ -n $environment ]]
    records="$ADMISSION_TEST_STATE/$environment.json"
    if [[ -e $records ]]; then
        jq '[.[0:1], .[1:]]' "$records"
    else
        echo '[[]]'
    fi
fi
MOCK
chmod +x "$fixture_root/bin/gh"

reset_fixture() {
    export ADMISSION_TEST_STATE="$fixture_root/state"
    rm -rf "$ADMISSION_TEST_STATE"
    mkdir "$ADMISSION_TEST_STATE"
    echo "$new_sha" > "$ADMISSION_TEST_STATE/main"
    unset JAVA_COMMIT
}

admit() {
    export GITHUB_RUN_NUMBER=$1
    export GITHUB_OUTPUT="$ADMISSION_TEST_STATE/output"
    : > "$GITHUB_OUTPUT"
    bash "$script" "${2:-build}" > "$ADMISSION_TEST_STATE/log" 2>&1
}

accepted() { grep -q '^accepted=true$' "$GITHUB_OUTPUT"; }
skipped() { grep -q '^accepted=false$' "$GITHUB_OUTPUT"; }
expect_failure() {
    if admit "$@"; then echo 'Expected admission failure' >&2; exit 1; fi
    if accepted; then echo 'Failure granted admission' >&2; exit 1; fi
}
cursor() { jq '[.[].payload.runNumber] | max' "$ADMISSION_TEST_STATE/pipeline-stage-${1:-build}.json"; }
passed() { printf 'PASS %s\n' "$1"; }

reset_fixture
admit 41
accepted
[[ $(cursor) == 41 ]]
[[ $(jq -c '.[0].payload | keys' "$ADMISSION_TEST_STATE/pipeline-stage-build.json") == '["runNumber"]' ]]
admit 41
accepted
[[ $(jq 'length' "$ADMISSION_TEST_STATE/pipeline-stage-build.json") == 1 ]]
passed 'initial admission is persisted; equal-run retries add no record'

admit 42
accepted
admit 41
skipped
[[ $(cursor) == 42 ]]
passed 'newer admission rejects a delayed first attempt or retry'

reset_fixture
export JAVA_COMMIT=$new_sha
admit 41 inputs
accepted
export JAVA_COMMIT=$old_sha
admit 42 inputs
accepted
grep -q "^source_sha=$old_sha$" "$GITHUB_OUTPUT"
passed 'new run intentionally rolls back to older contents'

export JAVA_COMMIT=$new_sha
admit 42 inputs
accepted
grep -q "^source_sha=$old_sha$" "$GITHUB_OUTPUT"
admit 41 inputs
skipped
passed 'input retry reuses saved selection and older input attempt is skipped'

reset_fixture
admit 41 inputs
accepted
grep -q "^source_sha=$new_sha$" "$GITHUB_OUTPUT"
records="$ADMISSION_TEST_STATE/pipeline-stage-inputs.json"
jq '.[-1].payload.pins["example/python"] = "saved-python"' "$records" > "$records.tmp"
mv "$records.tmp" "$records"
export JAVA_COMMIT=$old_sha
admit 42 inputs
unset JAVA_COMMIT
admit 43 inputs
grep -q "^source_sha=$old_sha$" "$GITHUB_OUTPUT"
[[ $(grep -c '/branches/main' "$ADMISSION_TEST_STATE/calls") == 1 ]]
[[ $(jq -r '.[-1].payload.pins["example/python"]' "$records") == saved-python ]]
passed 'bootstrap resolves main; later empty input keeps the saved Java selection'

reset_fixture
admit 42 build
admit 41 oci-image-packaging
accepted
admit 42 oci-image-packaging
admit 41 oci-image-packaging
skipped
[[ $(cursor build) == 42 && $(cursor oci-image-packaging) == 42 ]]
passed 'stages are independent and packaging-only retries check packaging state'

reset_fixture
admit 42
touch "$ADMISSION_TEST_STATE/read-error"
expect_failure 42
[[ $(cursor) == 42 ]]
passed 'read failure stops equal-run retry'

reset_fixture
touch "$ADMISSION_TEST_STATE/write-error"
expect_failure 41
rm "$ADMISSION_TEST_STATE/write-error"
touch "$ADMISSION_TEST_STATE/non-created"
expect_failure 41
passed 'write failure or non-created response grants no admission'

reset_fixture
touch "$ADMISSION_TEST_STATE/lost-response"
expect_failure 42 inputs
admit 41 inputs
skipped
export JAVA_COMMIT=$old_sha
admit 42 inputs
accepted
grep -q "^source_sha=$new_sha$" "$GITHUB_OUTPUT"
[[ $(jq 'length' "$ADMISSION_TEST_STATE/pipeline-stage-inputs.json") == 1 ]]
passed 'lost write response preserves the counter and original selection'

reset_fixture
touch "$ADMISSION_TEST_STATE/branch-error"
expect_failure 41 inputs
rm "$ADMISSION_TEST_STATE/branch-error"
export JAVA_COMMIT='invalid'
expect_failure 41 inputs
[[ ! -e "$ADMISSION_TEST_STATE/pipeline-stage-inputs.json" ]]
passed 'invalid or unavailable input is not recorded'

for number in 0 -1 1.5 invalid 9007199254740992; do
    reset_fixture
    expect_failure "$number"
done
passed 'invalid run counters fail closed'

for payload in '{"pins":{}}' '{"runNumber":-1}' '{"runNumber":"42"}' '"invalid JSON"'; do
    reset_fixture
    jq -n --argjson payload "$payload" '[{task:"stage-admission",payload:$payload}]' \
        > "$ADMISSION_TEST_STATE/pipeline-stage-build.json"
    expect_failure 43
done
passed 'malformed admission records fail closed'

reset_fixture
echo '[{"task":"other","payload":{"runNumber":42}}]' > "$ADMISSION_TEST_STATE/pipeline-stage-build.json"
expect_failure 43
echo '[{"task":"stage-admission","payload":"{\"runNumber\":42}"}]' > "$ADMISSION_TEST_STATE/pipeline-stage-build.json"
admit 41
skipped
admit 42
accepted
passed 'unexpected task fails closed; string payloads remain readable'

for order in '1 2 3' '1 3 2' '2 1 3' '2 3 1' '3 1 2' '3 2 1'; do
    reset_fixture
    highest=0
    for number in $order; do
        admit "$number"
        if (( number < highest )); then skipped; else accepted; highest=$number; fi
        [[ $(cursor) == "$highest" ]]
    done
done
passed 'arrival permutations cannot move a serialized stage counter backward'

reset_fixture
echo '[{"task":"stage-admission","payload":{"runNumber":43}},
       {"task":"stage-admission","payload":{"runNumber":41}},
       {"task":"stage-admission","payload":{"runNumber":42}}]' > "$ADMISSION_TEST_STATE/pipeline-stage-build.json"
admit 42
skipped
admit 43
accepted
passed 'highest counter is selected across pages independent of record order'
