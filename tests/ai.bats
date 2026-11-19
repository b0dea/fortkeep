load helpers

setup() {
  setup_env
  mkdir -p "$BATS_TEST_TMPDIR/c1"
  C1="$(cd "$BATS_TEST_TMPDIR/c1" && pwd -P)"   # devward_claude_dirs returns physical paths
  export DEVWARD_CLAUDE_DIRS="$C1"
  # A guard gets 5 s per probe; a Mac running several test files at once can overrun that, which the checks rightly
  # report as undecided. Tests that aren't about the timeout give it room; the timeout test sets its own.
  export DEVWARD_HOOK_TIMEOUT=30
}
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
guard_in() {  # SETTINGS_FILE HOOK_COMMAND
  jq -n --arg g "$2" '{hooks:{PreToolUse:[{matcher:"Bash|Write|Edit|MultiEdit", hooks:[{type:"command", command:$g}]}]}}' > "$1"
}

@test "BL-AI-01 npm at the shim in this run's shell → PASS; otherwise FAIL" {
  mkdir -p "$HOME/.safe-chain/shims"; printf '#!/bin/sh\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
  run env PATH="$HOME/.safe-chain/shims:/usr/bin:/bin" CLAUDECODE=1 /bin/bash "$REPO/checks/macos/BL-AI-01.sh"
  [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"from Claude Code"* ]]
  stub npm 'exit 0'
  chk BL-AI-01; [ "$(field status)" = FAIL ]
}
@test "BL-AI-02 no Claude config → NA" {
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none" chk BL-AI-02; [ "$(field status)" = NA ]
}
@test "BL-AI-02 no guard → FAIL" {
  chk BL-AI-02; [ "$(field status)" = FAIL ]
}
@test "BL-AI-02 the ready-made guard → PASS" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 a guard that refuses everything, or nothing → FAIL" {
  printf '#!/bin/sh\nexit 2\n' > "$BATS_TEST_TMPDIR/all"; chmod +x "$BATS_TEST_TMPDIR/all"
  guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/all"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/none"; chmod +x "$BATS_TEST_TMPDIR/none"
  guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/none"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
}
@test "BL-AI-02 a guard that answers with a deny decision counts" {
  cat > "$BATS_TEST_TMPDIR/json" <<'EOF'
#!/bin/bash
c="$(/usr/bin/jq -r '.tool_input.command // .tool_input.file_path')"
case "$c" in "ls -la"|*/notes.txt) exit 0 ;; esac
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'
EOF
  chmod +x "$BATS_TEST_TMPDIR/json"
  guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/json"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 the weakest folder decides; managed settings count for every folder" {
  C2="$BATS_TEST_TMPDIR/c2"; mkdir -p "$C2"
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  DEVWARD_CLAUDE_DIRS="$C1:$C2" chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *c2* ]]
  M="$DEVWARD_SYSROOT/Library/Application Support/ClaudeCode"; mkdir -p "$M"
  guard_in "$M/managed-settings.json" "$REPO/templates/agent-guard.sh"
  DEVWARD_CLAUDE_DIRS="$C1:$C2" chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 settings that aren't valid JSON → ERROR" {
  echo '{oops' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = ERROR ]
}
@test "BL-AI-02 Codex installed without hooks → FAIL" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  stub codex 'exit 0'
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Codex* ]]
}
codex_guard() {  # HOOK_COMMAND [MATCHER_FOR_EDITS] — ~/.codex/hooks.json running it on Bash and on apply_patch
  mkdir -p "$HOME/.codex"
  jq -n --arg g "$1" --arg m "${2:-^apply_patch$}" '{hooks:{PreToolUse:[{matcher:"^Bash$", hooks:[{type:"command", command:$g}]},
    {matcher:$m, hooks:[{type:"command", command:$g}]}]}}' > "$HOME/.codex/hooks.json"
}
picky() {  # a guard that lets through only `ls -la` and an edit of notes.txt, in Claude Code's or Codex's shape
  cat > "$BATS_TEST_TMPDIR/picky" <<'EOF'
#!/bin/bash
c="$(/usr/bin/jq -r '.tool_input.command // .tool_input.file_path')"
case "$c" in "ls -la"|*/notes.txt|*"Update File: "*/notes.txt$'\n'*) exit 0 ;; esac
exit 2
EOF
  chmod +x "$BATS_TEST_TMPDIR/picky"
}
@test "BL-AI-02 Codex alone is probed, never NA: no hooks → FAIL; a guard on Bash and apply_patch → PASS" {
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"; stub codex 'exit 0'
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none" chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"without a hooks.json in: ~/.codex"* ]]
  picky; codex_guard "$BATS_TEST_TMPDIR/picky"
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none" chk BL-AI-02; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"1 of 1"* ]]
}
@test "BL-AI-02 and BL-AI-03 pass for Codex alone with the ready-made guard on Bash and apply_patch" {
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"; stub codex 'exit 0'
  codex_guard "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = PASS ]
  mkdir -p "$HOME/.codex/rules"; touch "$HOME/.codex/rules/x.rules" "$HOME/.zshrc"
  chk BL-AI-03; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "5 of 5 agent control files are protected from agent edits" ]
}
@test "BL-AI-02 a Codex guard that misses apply_patch, or lets everything through → FAIL naming ~/.codex" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"; stub codex 'exit 0'
  picky; codex_guard "$BATS_TEST_TMPDIR/picky" '^Edit$'
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "No working guard in: ~/.codex."* ]]; [[ "$(field evidence)" == *"1 of 2"* ]]
  codex_guard /usr/bin/true
  chk BL-AI-02; [ "$(field status)" = FAIL ]
  echo '{oops' > "$HOME/.codex/hooks.json"
  chk BL-AI-02; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"~/.codex"* ]]
}
@test "BL-AI-02 a bad matcher regex → ERROR, never a silent no-guard" {
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash(", hooks:[{type:"command", command:"/bin/true"}]}]}}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *Could\ not\ decide* ]]
}
@test "BL-AI-02 managed settings that aren't valid JSON → ERROR" {
  M="$DEVWARD_SYSROOT/Library/Application Support/ClaudeCode"; mkdir -p "$M"
  echo '{oops' > "$M/managed-settings.json"
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *managed* ]]
}
@test "BL-AI-02 a hook that outlasts the timeout → ERROR" {
  printf '#!/bin/sh\nsleep 5\n' > "$BATS_TEST_TMPDIR/slow"; chmod +x "$BATS_TEST_TMPDIR/slow"
  guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/slow"
  DEVWARD_HOOK_TIMEOUT=1 chk BL-AI-02; [ "$(field status)" = ERROR ]
}
@test "BL-AI-02 FAIL outranks ERROR but the note names both folders" {
  C2="$BATS_TEST_TMPDIR/c2"; mkdir -p "$C2"; C3="$BATS_TEST_TMPDIR/c3"; mkdir -p "$C3"
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"; echo '{oops' > "$C3/settings.json"
  DEVWARD_CLAUDE_DIRS="$C1:$C2:$C3" chk BL-AI-02
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *c2* ]]; [[ "$(field note)" == *c3* ]]
}
@test "BL-AI-03 settings that aren't valid JSON → ERROR" {
  echo '{oops' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = ERROR ]
}
@test "BL-AI-03 managed settings that aren't valid JSON → ERROR" {
  M="$DEVWARD_SYSROOT/Library/Application Support/ClaudeCode"; mkdir -p "$M"
  echo '{oops' > "$M/managed-settings.json"
  jq -n '{permissions:{deny:["Edit(/settings.json)"]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *managed* ]]
  echo '{}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *managed* ]]
}
@test "BL-AI-03 a guard path with ~ and a shell prefix is found and must be protected" {
  mkdir -p "$HOME/.claude/hooks"; touch "$HOME/.claude/hooks/agent-guard.sh"
  guard_in "$C1/settings.json" '~/.claude/hooks/agent-guard.sh'
  jq '.permissions.deny = ["Edit(/settings.json)"]' "$C1/settings.json" > "$C1/s"; mv "$C1/s" "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *agent-guard.sh* ]]
  guard_in "$C1/settings.json" 'bash "$HOME/.claude/hooks/agent-guard.sh"'
  jq '.permissions.deny = ["Edit(/settings.json)"]' "$C1/settings.json" > "$C1/s"; mv "$C1/s" "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *agent-guard.sh* ]]
}
@test "BL-AI-03 Read rules don't count" {
  jq -n '{permissions:{deny:["Read(/settings.json)"]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]
}
@test "BL-AI-03 deny rules covering settings.json and the rc files → PASS" {
  touch "$HOME/.zshrc" "$HOME/.zprofile"
  jq -n --arg s "$C1/settings.json" '{permissions:{deny:["Edit(~/.z*)", ("Edit(/" + $s + ")")]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = PASS ]
}
@test "BL-AI-03 a rule relative to the config folder counts" {
  jq -n '{permissions:{deny:["Edit(/settings.json)"]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = PASS ]
}
@test "BL-AI-03 missing rules → FAIL naming the files" {
  touch "$HOME/.zshrc"
  echo '{}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *settings.json* ]]; [[ "$(field note)" == *.zshrc* ]]
}
@test "BL-AI-03 the guard script itself must be protected" {
  guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/g.sh"; touch "$BATS_TEST_TMPDIR/g.sh"
  jq '.permissions.deny = ["Edit(/settings.json)"]' "$C1/settings.json" > "$C1/s"; mv "$C1/s" "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *g.sh* ]]
}

managed() { M="$DEVWARD_SYSROOT/Library/Application Support/ClaudeCode"; mkdir -p "$M"; printf '%s\n' "$M/managed-settings.json"; }
root_stat() {  # STAT_OWNER/STAT_PERM apply to every path; STAT_ME_PATH names one path owned by "me"
  stub stat 'f=""; for a in "$@"; do case "$a" in %Su|%Sp) f="$a" ;; esac; done
for a in "$@"; do p="$a"; done
case "$f" in
  %Su) if [ "$p" = "${STAT_ME_PATH:-}" ]; then echo me; else echo "${STAT_OWNER:-root}"; fi ;;
  %Sp) echo "${STAT_PERM:--rw-r--r--}" ;;
  *) exec /usr/bin/stat "$@" ;;
esac'
}
good_managed() {
  g="$DEVWARD_SYSROOT/usr/local/lib/safe-chain-agent/agent-guard.sh"; mkdir -p "$(dirname "$g")"; cp "$REPO/templates/agent-guard.sh" "$g"
  jq --arg g "$g" '.hooks.PreToolUse[0].hooks[0].command = $g' "$REPO/templates/managed-settings.json" > "$(managed)"
}

@test "BL-AI-04 no managed settings → FAIL" {
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"No managed settings"* ]]
}
@test "BL-AI-04 root-owned file with bypass disabled and a root-owned guard → PASS" {
  root_stat; good_managed
  chk BL-AI-04; [ "$(field status)" = PASS ]
}
@test "BL-AI-04 a hook command of bash plus a quoted root-owned guard path → PASS" {
  root_stat; good_managed
  g="$DEVWARD_SYSROOT/usr/local/lib/safe-chain-agent/agent-guard.sh"
  jq --arg g "bash \"$g\"" '.hooks.PreToolUse[0].hooks[0].command = $g' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  chk BL-AI-04; [ "$(field status)" = PASS ]
}
@test "BL-AI-04 a file you own, bypass allowed, or a guard in your home → FAIL" {
  root_stat; good_managed
  STAT_OWNER=me chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *root* ]]
  jq 'del(.permissions.disableBypassPermissionsMode)' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *bypass* ]]
  good_managed; jq --arg g "$HOME/g.sh" '.hooks.PreToolUse[0].hooks[0].command = $g' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  touch "$HOME/g.sh"
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *hook* ]]
}
@test "BL-AI-04 a folder you own anywhere above the guard or the managed settings → FAIL (Homebrew's /usr/local on Intel)" {
  root_stat; good_managed
  chk BL-AI-04; [ "$(field status)" = PASS ]
  STAT_ME_PATH="$(cd "$DEVWARD_SYSROOT/usr/local" && pwd -P)" chk BL-AI-04
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"A hook script, or a folder above it"* ]]
  STAT_ME_PATH="$(cd "$DEVWARD_SYSROOT/Library" && pwd -P)" chk BL-AI-04
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"a folder above it isn't root-owned"* ]]
}
@test "BL-AI-04 a hook matcher that is not a valid regex → ERROR" {
  root_stat; good_managed
  jq '.hooks.PreToolUse[0].matcher = "("' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  chk BL-AI-04; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"couldn't read the hooks"* ]]
}
@test "BL-AI-05 a private ~/.cursor is never read: ERROR when nothing else was checked, a note otherwise" {
  mkdir -p "$HOME/.cursor"; jq -n '{mcpServers:{"hidden-srv":{command:"npx", args:["-y","x"]}}}' > "$HOME/.cursor/mcp.json"
  echo '~/.cursor' > "$DEVWARD_PRIVATE_PATHS"
  chk BL-AI-05; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]; [[ "$output" != *hidden-srv* ]]
  jq -n '{mcpServers:{p:{command:"npx", args:["pkg@1.0.0"]}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "BL-AI-05 no MCP servers → NA" {
  chk BL-AI-05; [ "$(field status)" = NA ]
}
@test "BL-AI-05 pinned, unpinned and remote servers are told apart; only names are reported" {
  jq -n '{mcpServers:{
    good:{command:"npx", args:["-y","@scope/server@1.2.3"], env:{TOKEN:"s3cret-value"}},
    loose:{command:"npx", args:["-y","some-server"]},
    latest:{command:"uvx", args:["tool@latest"]},
    remote:{type:"http", url:"https://mcp.example/x"}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = FAIL ]
  [[ "$(field evidence)" == "1 of 3"* ]]; [[ "$(field note)" == *loose* ]]; [[ "$(field note)" == *latest* ]]
  [[ "$output" != *s3cret* ]]; [[ "$output" != *some-server* ]]
}
@test "BL-AI-05 an npm major or minor version (pkg@1, pkg@1.2) is a range, not a pin" {
  jq -n '{mcpServers:{maj:{command:"npx", args:["-y","srv@1"]}, min:{command:"npx", args:["@s/srv@1.2"]},
    full:{command:"npx", args:["-y","@s/srv@1.2.3-beta.1"]}, py:{command:"uvx", args:["--from","pkg==2.0","pkg"]}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "2 of 4"* ]]
  [ "$(field note)" = "Not pinned: maj, min" ]
}
@test "BL-AI-05 project-scoped servers in the state file count; all pinned → PASS" {
  jq -n '{projects:{"/x":{mcpServers:{p:{command:"uvx", args:["--from","pkg==2.0","pkg"]}}}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = PASS ]
}
@test "BL-AI-05 an unreadable state file next to a pinned server → ERROR naming it" {
  jq -n '{mcpServers:{p:{command:"npx", args:["pkg@1.0.0"]}}}' > "$HOME/.claude.json"
  echo '{oops' > "$C1/.claude.json"
  chk BL-AI-05; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *".claude.json"* ]]
}
@test "BL-AI-05 an unreadable file plus an unpinned server → FAIL that also names the unreadable file" {
  jq -n '{mcpServers:{loose:{command:"npx", args:["-y","some-server"]}}}' > "$HOME/.claude.json"
  echo '{oops' > "$C1/.claude.json"
  chk BL-AI-05; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *loose* ]]; [[ "$(field note)" == *"Could not read"* ]]
}
@test "BL-AI-06 sandbox on in every folder → PASS; off → FAIL" {
  echo '{"sandbox":{"enabled":true}}' > "$C1/settings.json"
  chk BL-AI-06; [ "$(field status)" = PASS ]
  echo '{}' > "$C1/settings.json"
  chk BL-AI-06; [ "$(field status)" = FAIL ]
}
@test "BL-AI-06 invalid JSON is ERROR, a missing settings.json is off, and FAIL outranks ERROR" {
  echo '{oops' > "$C1/settings.json"
  chk BL-AI-06; [ "$(field status)" = ERROR ]
  rm "$C1/settings.json"
  chk BL-AI-06; [ "$(field status)" = FAIL ]
  mkdir -p "$BATS_TEST_TMPDIR/c2"; C2="$(cd "$BATS_TEST_TMPDIR/c2" && pwd -P)"
  echo '{oops' > "$C1/settings.json"; echo '{}' > "$C2/settings.json"
  DEVWARD_CLAUDE_DIRS="$C1:$C2" chk BL-AI-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not read"* ]]
}
@test "BL-AI-04 group-writable or other-writable managed settings → FAIL" {
  root_stat; good_managed
  STAT_PERM=-rw-rw-r-- chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *root* ]]
  STAT_PERM=-rw-r--rw- chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *root* ]]
}
@test "BL-AI-04 a guard whose folder is not root-owned → FAIL" {
  root_stat; good_managed
  STAT_ME_PATH="$DEVWARD_SYSROOT/usr/local/lib/safe-chain-agent" chk BL-AI-04
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"hook script"* ]]
}
@test "BL-AI-04 Codex alone is checked, never NA: its root-owned requirements decide, with no Claude Code managed settings asked for" {
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"
  chk BL-AI-04; [ "$(field status)" = NA ]
  root_stat; stub codex 'exit 0'
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"without a root-owned /etc/codex/requirements.toml"* ]]
  [[ "$(field note)" != *managed* ]]
  R="$DEVWARD_SYSROOT/etc/codex/requirements.toml"; mkdir -p "$(dirname "$R")"
  printf 'allowed_sandbox_modes = ["read-only", "workspace-write"]\n' > "$R"
  chk BL-AI-04; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *requirements.toml* ]]
}
@test "BL-AI-04 Codex requirements must limit the sandbox modes: missing, under a table, or allowing danger-full-access → FAIL" {
  root_stat; good_managed; stub codex 'exit 0'
  R="$DEVWARD_SYSROOT/etc/codex/requirements.toml"; mkdir -p "$(dirname "$R")"
  printf '[rules]\nprefix_rules = []\n' > "$R"
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"doesn't set allowed_sandbox_modes"* ]]
  printf '[rules]\nallowed_sandbox_modes = ["read-only"]\n' > "$R"
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"doesn't set allowed_sandbox_modes"* ]]
  printf 'allowed_sandbox_modes = [\n  "read-only",\n  "danger-full-access",\n]\n' > "$R"
  chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *danger-full-access* ]]
  printf '# allowed_sandbox_modes = ["danger-full-access"]\nallowed_sandbox_modes = [\n  "read-only", # not "danger-full-access" ]\n  "workspace-write",\n]\n\n[rules]\nprefix_rules = []\n' > "$R"
  chk BL-AI-04; [ "$(field status)" = PASS ]
}
@test "BL-AI-04 a root-owned guard that differs from your copy of the same name, with no template of that name → FAIL: compare first" {
  root_stat; good_managed
  g="$DEVWARD_SYSROOT/usr/local/lib/safe-chain-agent/agent-guard"; printf 'print("v1")\n' > "$g"
  jq --arg g "/usr/bin/python3 $g || exit 2" '.hooks.PreToolUse[0].hooks[0].command = $g' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  mkdir -p "$HOME/.local/bin"; printf 'print("v2")\n' > "$HOME/.local/bin/agent-guard"
  guard_in "$C1/settings.json" "/usr/bin/python3 $HOME/.local/bin/agent-guard || exit 2"
  chk BL-AI-04; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"root-owned copy of agent-guard differs from your copy"* ]]
  [[ "$(field note)" == *"compare them first: diff /usr/local/lib/safe-chain-agent/agent-guard ~/.local/bin/agent-guard."* ]]
  [[ "$(field note)" == *"sudo install -o root -g wheel -m 755 ~/.local/bin/agent-guard /usr/local/lib/safe-chain-agent/agent-guard" ]]
  cp "$g" "$HOME/.local/bin/agent-guard"
  chk BL-AI-04; [ "$(field status)" = PASS ]
  # A path the shell would misread is quoted for typing, and ~ stays outside the quoting.
  mkdir -p "$HOME/a&b"; printf 'print("v3")\n' > "$HOME/a&b/agent-guard"
  guard_in "$C1/settings.json" "/usr/bin/python3 $HOME/a&b/agent-guard || exit 2"
  chk BL-AI-04; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *'sudo install -o root -g wheel -m 755 ~/a\&b/agent-guard /usr/local/lib/safe-chain-agent/agent-guard' ]]
}
@test "BL-AI-04 with this repo's template of the same name, the template is the source, never your copy" {
  root_stat; good_managed
  export DEVWARD_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$DEVWARD_REPO/templates"; T="$DEVWARD_REPO/templates/agent-guard"
  g="$DEVWARD_SYSROOT/usr/local/lib/safe-chain-agent/agent-guard"
  jq --arg g "/usr/bin/python3 $g || exit 2" '.hooks.PreToolUse[0].hooks[0].command = $g' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  mkdir -p "$HOME/.local/bin"; guard_in "$C1/settings.json" "/usr/bin/python3 $HOME/.local/bin/agent-guard || exit 2"
  # Root copy matches the template: only your copy is replaced, no sudo.
  printf 'print("v1")\n' > "$T"; cp "$T" "$g"; printf 'print("evil")\n' > "$HOME/.local/bin/agent-guard"
  chk BL-AI-04; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"Your copy of agent-guard differs from the root-owned one, which matches this repo's template"* ]]
  [[ "$(field note)" == *"install -m 755 $T ~/.local/bin/agent-guard" ]]; [[ "$(field note)" != *sudo* ]]
  # Root copy stale: the template goes to root, and your copy is updated from it too when it differs.
  printf 'print("v0")\n' > "$g"
  chk BL-AI-04; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"sudo install -o root -g wheel -m 755 $T /usr/local/lib/safe-chain-agent/agent-guard, then update your copy from it: install -m 755 $T ~/.local/bin/agent-guard" ]]
  [[ "$(field note)" != *"sudo install -o root -g wheel -m 755 ~/.local/bin/agent-guard"* ]]
  cp "$T" "$HOME/.local/bin/agent-guard"
  chk BL-AI-04; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"sudo install -o root -g wheel -m 755 $T /usr/local/lib/safe-chain-agent/agent-guard" ]]; [[ "$(field note)" != *"update your copy"* ]]
}
@test "BL-AI-06 managed sandbox off with no config folders → FAIL; invalid managed file → ERROR; string true is off" {
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"; M="$(dirname "$(managed)")"
  echo '{}' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"managed settings"* ]]
  echo '{"sandbox":{"enabled":"true"}}' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = FAIL ]
  echo '{oops' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = ERROR ]
}
@test "BL-AI-06 managed sandbox off wins over a folder that turns it on → FAIL naming the managed settings" {
  echo '{"sandbox":{"enabled":true}}' > "$C1/settings.json"
  echo '{"sandbox":{"enabled":false}}' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Sandbox off" ]; [[ "$(field note)" == *"managed settings"* ]]
  echo '{"sandbox":{"enabled":"true"}}' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"managed settings"* ]]
  echo '{}' > "$(managed)"
  chk BL-AI-06; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 a folder with disableAllHooks contributes no hooks; managed hooks still count for it" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  jq '.disableAllHooks = true' "$C1/settings.json" > "$C1/s"; mv "$C1/s" "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *disableAllHooks* ]]
  guard_in "$(managed)" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 managed disableAllHooks switches off every hook, managed ones included" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  guard_in "$(managed)" "$REPO/templates/agent-guard.sh"
  jq '.disableAllHooks = true' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *disableAllHooks* ]]
}
@test "BL-AI-02 managed allowManagedHooksOnly: only managed hooks count" {
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  echo '{"allowManagedHooksOnly":true}' > "$(managed)"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *allowManagedHooksOnly* ]]
  guard_in "$(managed)" "$REPO/templates/agent-guard.sh"
  jq '.allowManagedHooksOnly = true' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  echo '{}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-03 the PATH file BL-SC-02 installs must be protected when it exists" {
  jq -n '{permissions:{deny:["Edit(/settings.json)"]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = PASS ]
  mkdir -p "$HOME/.config/devward"; touch "$HOME/.config/devward/path-front.sh"
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"~/.config/devward/path-front.sh"* ]]
  jq -n '{permissions:{deny:["Edit(/settings.json)", "Edit(~/.config/devward/**)"]}}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 a guard on Bash only misses the Write probe → FAIL" {
  jq -n --arg g "$REPO/templates/agent-guard.sh" '{hooks:{PreToolUse:[{matcher:"Bash", hooks:[{type:"command", command:$g}]}]}}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
}
@test "BL-AI-02 a guard that misses one of the newer probes → FAIL" {
  cat > "$BATS_TEST_TMPDIR/old" <<'G'
#!/bin/bash
i="$(/usr/bin/jq -r '.tool_input.command // .tool_input.file_path')"
case "$i" in *woff2*|*"ls -la"*|*/notes.txt) exit 0 ;; esac
exit 2
G
  chmod +x "$BATS_TEST_TMPDIR/old"; guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/old"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
}
@test "BL-AI-02 the deprecated decision block answer counts as a refusal" {
  cat > "$BATS_TEST_TMPDIR/dep" <<'G'
#!/bin/bash
i="$(/usr/bin/jq -r '.tool_input.command // .tool_input.file_path')"
case "$i" in "ls -la"|*/notes.txt) exit 0 ;; esac
echo '{"decision":"block","reason":"no"}'
G
  chmod +x "$BATS_TEST_TMPDIR/dep"; guard_in "$C1/settings.json" "$BATS_TEST_TMPDIR/dep"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 a guard shipped in an enabled plugin counts, with CLAUDE_PLUGIN_ROOT set" {
  PL="$BATS_TEST_TMPDIR/pl/guard/1.0.0"; mkdir -p "$PL/hooks" "$C1/plugins"
  cp "$REPO/templates/agent-guard.sh" "$PL/hooks/agent-guard.sh"
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash|Write|Edit|MultiEdit", hooks:[{type:"command", command:"\"${CLAUDE_PLUGIN_ROOT}/hooks/agent-guard.sh\""}]}]}}' > "$PL/hooks/hooks.json"
  jq -n --arg p "$PL" '{version:2, plugins:{"guard@local":[{scope:"user", installPath:$p}]}}' > "$C1/plugins/installed_plugins.json"
  echo '{"enabledPlugins":{"guard@local":false}}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
  echo '{"enabledPlugins":{"guard@local":true}}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = PASS ]
}
@test "BL-AI-02 hooks only in the config folder's settings.local.json don't count, and the note says why" {
  guard_in "$C1/settings.local.json" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *settings.local.json* ]]
}
@test "BL-AI-02 a project-scoped plugin doesn't count; an unreadable plugin list → ERROR" {
  PL="$BATS_TEST_TMPDIR/pl/guard/1.0.0"; mkdir -p "$PL/hooks" "$C1/plugins"
  cp "$REPO/templates/agent-guard.sh" "$PL/hooks/agent-guard.sh"
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash|Write|Edit|MultiEdit", hooks:[{type:"command", command:"\"${CLAUDE_PLUGIN_ROOT}/hooks/agent-guard.sh\""}]}]}}' > "$PL/hooks/hooks.json"
  jq -n --arg p "$PL" '{version:2, plugins:{"guard@local":[{scope:"project", installPath:$p}]}}' > "$C1/plugins/installed_plugins.json"
  echo '{"enabledPlugins":{"guard@local":true}}' > "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = FAIL ]
  echo '{oops' > "$C1/plugins/installed_plugins.json"
  chk BL-AI-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *c1* ]]
}
@test "managed-settings.sh adds a deny rule for a CLAUDE_CONFIG_DIR folder; BL-AI-03 then counts that settings.json" {
  run /bin/bash "$REPO/checks/managed-settings.sh"; [ "$status" -eq 0 ]
  jq -e --arg r "Edit(/$C1/settings.json)" '.permissions.deny | index($r) != null' <<<"$output"
  printf '%s\n' "$output" > "$(managed)"
  echo '{}' > "$C1/settings.json"
  chk BL-AI-03; [ "$(field status)" = PASS ]
}
@test "managed-settings.sh with only ~/.claude prints the template's rules unchanged" {
  mkdir -p "$HOME/.claude"
  DEVWARD_CLAUDE_DIRS="$HOME/.claude" run /bin/bash "$REPO/checks/managed-settings.sh"; [ "$status" -eq 0 ]
  [ "$(jq -S . <<<"$output")" = "$(jq -S . "$REPO/templates/managed-settings.json")" ]
}
@test "managed-settings.sh changes nothing on disk" {
  before="$(find "$HOME" "$DEVWARD_SYSROOT" "$REPO/templates" -exec stat -f '%N %m %z' {} + | shasum)"
  run /bin/bash "$REPO/checks/managed-settings.sh"; [ "$status" -eq 0 ]
  [ "$(find "$HOME" "$DEVWARD_SYSROOT" "$REPO/templates" -exec stat -f '%N %m %z' {} + | shasum)" = "$before" ]
}
@test "the managed-settings template denies edits to every kind of file the guard template protects" {
  rules="$(jq -r '.permissions.deny[] | select(startswith("Edit(")) | .[5:-1] | gsub("\\*\\*"; "*")' "$REPO/templates/managed-settings.json")"
  for p in '~/.zshrc' '~/.zprofile' '~/.zshenv' '~/.zlogin' '~/.bashrc' '~/.bash_profile' '~/.profile' \
    '~/.claude/settings.json' '~/.claude/settings.local.json' '~/.claude.json' \
    '//Library/Application Support/ClaudeCode/managed-settings.json' '//usr/local/lib/safe-chain-agent/agent-guard.sh' \
    '~/Library/LaunchAgents/x.plist' '~/.safe-chain/shims/npm' '~/.codex/hooks.json' '~/.codex/rules/x.rules' \
    '~/.config/devward/path-front.sh' '~/.claude/plugins/cache/m/p/hooks/hooks.json' '~/.claude/plugins/installed_plugins.json'; do
    case "$p" in '~/'*) f="$HOME/${p#\~/}" ;; *) f="${p#/}" ;; esac
    jq -cn --arg p "$f" '{tool_name:"Write", tool_input:{file_path:$p, content:"x"}}' | "$REPO/templates/agent-guard.sh" 2>/dev/null && false
    hit=0
    while IFS= read -r r; do
      # shellcheck disable=SC2254 # deny rules are glob patterns
      case "$p" in $r) hit=1; break ;; esac
    done <<<"$rules"
    [ "$hit" -eq 1 ] || { echo "no Edit deny rule for $p"; false; }
  done
}
@test "BL-AI-04 a file you own is a FAIL even when its contents can't be read, and the note names them" {
  root_stat; good_managed
  echo '{oops' > "$(managed)"
  STAT_OWNER=me chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *root* ]]; [[ "$(field note)" == *"not valid JSON"* ]]
  chk BL-AI-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  good_managed; jq '.hooks.PreToolUse[0].matcher = "("' "$(managed)" > "$BATS_TEST_TMPDIR/m"; mv "$BATS_TEST_TMPDIR/m" "$(managed)"
  STAT_OWNER=me chk BL-AI-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *root* ]]; [[ "$(field note)" == *"couldn't read the hooks"* ]]
}
@test "the BL-AI-04 lesson's check step prints true only when the generated managed settings are sound" {
  L="$REPO/teach/BL-AI-04.md"
  step() { grep -F -- "$1" "$L" | head -n 1 | sed 's/^[0-9]*\. `\([^`]*\)`.*/\1/'; }  # TEXT — the command of the numbered step holding TEXT
  tmp="$(step 't="$(mktemp -d)"')"; gen="$(step 'checks/managed-settings.sh > "$t/managed-settings.json"')"
  check="$(step "jq -e '.permissions.deny | length > 0'")"
  [ -n "$tmp" ] && [ -n "$gen" ] && [ -n "$check" ]
  grep -q 'must print `true`.*stop' "$L"
  # The admin steps come after the check, and the check is a step of its own.
  [ "$(grep -n -F "$check" "$L" | cut -d: -f1)" -lt "$(grep -n -F 'sudo install' "$L" | head -n 1 | cut -d: -f1)" ]
  F="$BATS_TEST_TMPDIR/fake"; mkdir -p "$F/checks"
  printf '#!/bin/bash\nprintf "{\\"permissions\\": {"\nexit 1\n' > "$F/checks/managed-settings.sh"; chmod +x "$F/checks/managed-settings.sh"
  run env TMPDIR="$BATS_TEST_TMPDIR" /bin/bash -c "cd '$F'; $tmp; $gen; $check"; [ "$output" != true ]
  printf '#!/bin/bash\necho "{}"\n' > "$F/checks/managed-settings.sh"
  run env TMPDIR="$BATS_TEST_TMPDIR" /bin/bash -c "cd '$F'; $tmp; $gen; $check"; [ "$output" != true ]
  run env TMPDIR="$BATS_TEST_TMPDIR" /bin/bash -c "cd '$REPO'; $tmp; $gen; $check"; [ "$status" -eq 0 ]; [ "$output" = true ]
}
@test "BL-AI-03 Codex alone is probed, never NA: its apply_patch guard must refuse edits to each file that controls it" {
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"; stub codex 'exit 0'
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"refuse edits to: ~/.codex/hooks.json, ~/.codex/config.toml"* ]]
  picky; codex_guard "$BATS_TEST_TMPDIR/picky"; mkdir -p "$HOME/.codex/rules"; touch "$HOME/.codex/rules/x.rules" "$HOME/.zshrc"
  chk BL-AI-03; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "5 of 5 agent control files are protected from agent edits" ]
  codex_guard /usr/bin/true
  chk BL-AI-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"~/.codex/rules/x.rules"* ]]; [[ "$(field note)" == *"~/.zshrc"* ]]
}
@test "BL-AI-03 a symlinked config folder is matched by its real path" {
  mkdir -p "$BATS_TEST_TMPDIR/real-claude"; ln -s "$BATS_TEST_TMPDIR/real-claude" "$HOME/.claude"
  jq -n '{permissions:{deny:["Edit(~/.claude/settings.json)"]}}' > "$BATS_TEST_TMPDIR/real-claude/settings.json"
  DEVWARD_CLAUDE_DIRS="$HOME/.claude" chk BL-AI-03; [ "$(field status)" = PASS ]
}
@test "BL-AI-05 flags that take a value are skipped; --from, --spec and -p name the package" {
  jq -n '{mcpServers:{
    a:{command:"npx", args:["--registry","https://r.example","pkg@1.0.0"]},
    b:{command:"pipx", args:["run","tool==2.1"]},
    c:{command:"pipx", args:["run","--spec","tool==2.1","tool"]},
    d:{command:"npx", args:["-p","x@1.0.0","cmd"]}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = PASS ]
  jq -n '{mcpServers:{e:{command:"uvx", args:["--python","3.12","tool"]}}}' > "$HOME/.claude.json"
  chk BL-AI-05; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *e* ]]
}

@test "managed-settings.sh adds a deny rule for every aimux profile Claude has used" {
  unset DEVWARD_CLAUDE_DIRS
  P="$HOME/.aimux/profiles"; mkdir -p "$HOME/.claude" "$P/a/projects" "$P/b" "$P/c"; echo '{}' > "$P/b/settings.json"
  Pp="$(cd "$P" && pwd -P)"
  run /bin/bash "$REPO/checks/managed-settings.sh"; [ "$status" -eq 0 ]
  jq -e --arg a "Edit(/$Pp/a/settings.json)" --arg b "Edit(/$Pp/b/settings.json)" \
    '.permissions.deny | index($a) != null and index($b) != null' <<<"$output"
  [ "$(jq '.permissions.deny | length' <<<"$output")" -eq "$(( $(jq '.permissions.deny | length' "$REPO/templates/managed-settings.json") + 2 ))" ]
}
@test "BL-AI-02 counts an aimux profile: a profile without the guard fails the control" {
  unset DEVWARD_CLAUDE_DIRS
  mkdir -p "$HOME/.claude" "$HOME/.aimux/profiles/p/projects"
  guard_in "$HOME/.claude/settings.json" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"aimux/profiles/p"* ]]
}

@test "BL-AI-02 a private folder left out of the others: the result keeps its verdict and notes the exclusion, never the path" {
  mkdir -p "$BATS_TEST_TMPDIR/secret"; S1="$(cd "$BATS_TEST_TMPDIR/secret" && pwd -P)"
  export DEVWARD_CLAUDE_DIRS="$C1:$S1"; printf '%s\n' "$S1" > "$DEVWARD_PRIVATE_PATHS"
  guard_in "$C1/settings.json" "$REPO/templates/agent-guard.sh"
  chk BL-AI-02; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"a private folder was excluded"* ]]; [[ "$output" != *secret* ]]
  rm "$C1/settings.json"
  chk BL-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"a private folder was excluded)" ]]; [[ "$output" != *secret* ]]
}
@test "BL-AI-02 and BL-AI-03: every folder private → ERROR, not 'not set up'" {
  printf '%s\n' "$C1" > "$DEVWARD_PRIVATE_PATHS"
  for id in BL-AI-02 BL-AI-03; do
    chk $id; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"Could not check every Claude Code folder"* ]]
    [ "$(field note)" = "a private folder was excluded" ]; [[ "$output" != *c1* ]]
  done
}
@test "BL-AI-05 no servers but a private folder was left out → ERROR, not NA" {
  printf '%s\n' "$C1" > "$DEVWARD_PRIVATE_PATHS"
  chk BL-AI-05; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"Could not check every Claude Code folder"* ]]
  [ "$(field note)" = "a private folder was excluded" ]
}
@test "BL-AI-06 Codex alone is checked, never NA: sandboxed by default, off only with sandbox_mode danger-full-access" {
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/none"; stub codex 'exit 0'; mkdir -p "$HOME/.codex"
  chk BL-AI-06; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *Codex* ]]
  printf '# sandbox_mode = "danger-full-access"\nsandbox_mode = "workspace-write"\n[profiles.x]\nsandbox_mode = "danger-full-access"\n' > "$HOME/.codex/config.toml"
  chk BL-AI-06; [ "$(field status)" = PASS ]
  printf 'model = "x"\nsandbox_mode = "danger-full-access"\n' > "$HOME/.codex/config.toml"
  chk BL-AI-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"~/.codex/config.toml"* ]]
  echo '{"sandbox":{"enabled":true}}' > "$C1/settings.json"
  DEVWARD_CLAUDE_DIRS="$C1" chk BL-AI-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"~/.codex/config.toml"* ]]
  echo '~/.codex' > "$DEVWARD_PRIVATE_PATHS"
  chk BL-AI-06; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]
}
@test "BL-AI-06 nothing found and a private folder left out → ERROR, not NA" {
  printf '%s\n' "$C1" > "$DEVWARD_PRIVATE_PATHS"
  chk BL-AI-06; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]
}
