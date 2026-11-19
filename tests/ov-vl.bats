load helpers

setup() {
  setup_env
  mkdir -p "$BATS_TEST_TMPDIR/c1"
  C1="$(cd "$BATS_TEST_TMPDIR/c1" && pwd -P)"   # devward_claude_dirs returns physical paths
  export DEVWARD_CLAUDE_DIRS="$C1"
  # The checks ask a login shell, where /etc/zprofile's path_helper puts /etc/paths.d entries (such as
  # /opt/homebrew/bin) first; ~/.zprofile runs after it, so the stubs win as they would on any Mac.
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zprofile"
}
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
brew_varlock() {  # a varlock installed by Homebrew, and a brew that lists $FULL as its formula and $PINNED as pinned
  V="$BATS_TEST_TMPDIR/hb/Cellar/varlock/1.23.0/bin"; mkdir -p "$V"
  printf '#!/bin/sh\n' > "$V/varlock"; chmod +x "$V/varlock"; ln -s "$V/varlock" "$BATS_TEST_TMPDIR/bin/varlock"
  stub brew 'case "$*" in
  "list --formula --full-name") printf "%s\n" git "${FULL-dmno-dev/tap/varlock}" ;;
  "list --pinned") printf "%s\n" ${PINNED-varlock} ;;
  *) echo "unexpected: $*" >&2; exit 9 ;;
esac
exit "${BREW_RC:-0}"'
}
guard_in() {  # SETTINGS_FILE HOOK_COMMAND
  jq -n --arg g "$2" '{hooks:{PreToolUse:[{matcher:"Bash|Write|Edit|MultiEdit", hooks:[{type:"command", command:$g}]}]}}' > "$1"
}

@test "OV-VL-01 from the official tap and pinned → PASS with its version; not pinned → FAIL saying how to pin" {
  brew_varlock
  chk OV-VL-01; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "varlock 1.23.0 from dmno-dev/tap/varlock, pinned" ]
  PINNED=ghidra chk OV-VL-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"is not pinned"* ]]; [[ "$(field note)" == *"brew pin varlock"* ]]
}
@test "OV-VL-01 from another formula → FAIL naming it; brew failing → ERROR" {
  brew_varlock
  FULL=varlock chk OV-VL-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "varlock 1.23.0 comes from varlock, not the official tap" ]
  BREW_RC=1 chk OV-VL-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "OV-VL-01 not installed → FAIL; installed outside Homebrew → FAIL naming where" {
  chk OV-VL-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"brew install dmno-dev/tap/varlock"* ]]
  stub varlock 'exit 0'
  chk OV-VL-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed by Homebrew"* ]]
  [[ "$(field note)" == *"brew install dmno-dev/tap/varlock"* ]]
}
@test "OV-VL-02 reads only telemetryDisabled: true → PASS; missing or false → FAIL; no varlock → NA; bad JSON → ERROR" {
  mkdir -p "$HOME/.config/varlock"
  echo '{"anonymousId":"id-must-not-show","telemetryDisabled":true}' > "$HOME/.config/varlock/config.json"
  chk OV-VL-02; [ "$(field status)" = PASS ]; [[ "$output" != *id-must-not-show* ]]
  echo '{"anonymousId":"id-must-not-show","telemetryDisabled":false}' > "$HOME/.config/varlock/config.json"
  chk OV-VL-02; [ "$(field status)" = NA ]
  stub varlock 'exit 0'
  chk OV-VL-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"varlock telemetry disable"* ]]; [[ "$output" != *id-must-not-show* ]]
  rm "$HOME/.config/varlock/config.json"
  chk OV-VL-02; [ "$(field status)" = FAIL ]
  echo '{oops' > "$HOME/.config/varlock/config.json"
  chk OV-VL-02; [ "$(field status)" = ERROR ]
}
@test "OV-VL-03 the ready-made guard → PASS; no guard → FAIL; no Claude Code → NA" {
  chk OV-VL-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"templates/agent-guard.sh"* ]]
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  chk OV-VL-03; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"1 of 1"* ]]
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none" chk OV-VL-03; [ "$(field status)" = NA ]
}
@test "OV-VL-03 a guard that misses varlock, or refuses varlock run too → FAIL" {
  cat > "$BATS_TEST_TMPDIR/g" <<'G'
#!/bin/bash
i="$(/usr/bin/jq -r '.tool_input.command')"
case "$i" in *"${MATCH:-nothing}"*) exit 2 ;; esac
exit 0
G
  chmod +x "$BATS_TEST_TMPDIR/g"; guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/g"
  MATCH=printenv chk OV-VL-03; [ "$(field status)" = FAIL ]
  MATCH=varlock chk OV-VL-03; [ "$(field status)" = FAIL ]
  MATCH=nothing chk OV-VL-03; [ "$(field status)" = FAIL ]
}
@test "OV-VL-03 a hook that outlasts the timeout → ERROR" {
  guard_in "$C1/settings.json" "sleep 5"
  DEVWARD_HOOK_TIMEOUT=1 chk OV-VL-03; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "detect.sh suggests secrets-varlock when varlock is installed" {
  stub varlock 'exit 0'
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/detect.sh"
  [ "$(jq -r .varlock <<<"$output")" = true ]; [ "$(jq -c .suggest_overlays <<<"$output")" = '["secrets-varlock"]' ]
}
