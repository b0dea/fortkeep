load helpers

# Decision 18: session start, the fix library and the scripts a person runs trust a copy only when it is exactly a
# signed release with nothing changed, ignored files where agents load config included. Each test builds a throwaway
# release (helpers.bash) and runs in a person's session.
setup() {
  setup_env; person_session
  T="$BATS_TEST_TMPDIR/copy"; release_tree "$T" checks fixes controls templates .claude/hooks
  export CLAUDE_PROJECT_DIR="$T"
}
H="$BATS_TEST_DIRNAME/../.claude/hooks"
start() { run "$H/session-start.sh" </dev/null; [ "$status" -eq 0 ]; msg="$(jq -r .systemMessage <<<"$output")"; }
clean() { start; [[ "$msg" != *WARNING* ]]; }
warned() { start; [[ "$msg" == *"WARNING"*"$1"*"Don't run fixes; reinstall a signed release unless you made these changes yourself."* ]]; }

@test "a signed release with nothing changed starts with no warning, and the release is recorded as run" {
  clean
  [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.1.0 ]
}
@test "a release that can't be recorded as run says so at session start: downgrade warnings and signer rollover stop" {
  chmod 500 "$HOME/.config/fortkeep"
  run "$H/session-start.sh" </dev/null; chmod 700 "$HOME/.config/fortkeep"   # writable again before any check fails
  [ "$status" -eq 0 ]; msg="$(jq -r .systemMessage <<<"$output")"
  [[ "$msg" == *"WARNING"*"could not record"* ]]
  [ ! -e "$HOME/.config/fortkeep/highest-release" ]
}
@test "a commit after the release is not a release, so committing can't hide a change (A2)" {
  echo evil >> "$T/checks/run.sh"; commit "$T"
  warned "not on a signed release"
}
@test "a tag signed by a key the release doesn't list is not a release" {
  ssh-keygen -q -t ed25519 -N '' -C other -f "$BATS_TEST_TMPDIR/other"
  git -C "$T" tag -d v0.1.0 >/dev/null
  git -C "$T" -c user.name=t -c user.email=t@example.com -c gpg.format=ssh -c user.signingkey="$BATS_TEST_TMPDIR/other" \
    tag -s -m "b0dea/fortkeep v0.1.0" v0.1.0
  warned "not on a signed release"
}
@test "a release that names its own new signer doesn't vouch for itself: the signers this Mac trusted first decide" {
  clean
  ssh-keygen -q -t ed25519 -N '' -C evil -f "$BATS_TEST_TMPDIR/evil"
  printf 'evil namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$BATS_TEST_TMPDIR/evil.pub")" >> "$T/.github/allowed_signers"
  echo evil >> "$T/checks/run.sh"; commit "$T"
  git -C "$T" -c user.name=t -c user.email=t@example.com -c gpg.format=ssh -c user.signingkey="$BATS_TEST_TMPDIR/evil" \
    tag -s -m "b0dea/fortkeep v999.0.0" v999.0.0
  warned "not on a signed release"
  [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.1.0 ]
  # a release a trusted key signed may name the next signers
  echo next >> "$T/controls/controls.json"; commit "$T"; sign_release "$T" v0.2.0
  clean; [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.2.0 ]
}
@test "the local-changes warning names the file an agent added" {
  mkdir -p "$T/.claude"; echo '{}' > "$T/.claude/settings.local.json"
  warned ".claude/settings.local.json"
}
@test "worktree-only git settings and settings that run a credential helper count as local changes (A5)" {
  git -C "$T" config core.repositoryformatversion 1; git -C "$T" config extensions.worktreeConfig true
  clean
  git -C "$T" config --worktree filter.x.smudge cat; warned "local changes"; git -C "$T" config --worktree --unset filter.x.smudge
  git -C "$T" config --worktree core.attributesFile /tmp/a; warned "local changes"; git -C "$T" config --worktree --unset core.attributesFile
  for kv in 'credential.helper=!touch /tmp/x' 'credential.https://github.com.helper=x' core.askPass=/tmp/x 'url.https://evil.example/.insteadOf=https://github.com/'; do
    git -C "$T" config "${kv%%=*}" "${kv#*=}"; warned "local changes"; git -C "$T" config --unset "${kv%%=*}"
  done
}
@test "ignored files where agents load config count as local changes (A5)" {
  printf '.opencode/*\n.claude/settings.local.json\nCLAUDE.local.md\nAGENTS.override.md\n.mcp.json\n.codex/config.toml\n' > "$T/.gitignore"
  commit "$T"; git -C "$T" tag -d v0.1.0 >/dev/null; sign_release "$T" v0.1.0
  clean
  for f in .opencode/plugin/evil.ts .opencode/opencode.json .opencode/tool/x.ts .opencode/command/posture.md \
    .claude/settings.local.json CLAUDE.local.md AGENTS.override.md .mcp.json .codex/config.toml teach/CLAUDE.md; do
    mkdir -p "$T/$(dirname "$f")"; echo x > "$T/$f"
    warned "local changes"
    rm "$T/$f"
  done
  # OpenCode's own plugin library in .opencode is not a plugin
  mkdir -p "$T/.opencode/node_modules/x"; echo x > "$T/.opencode/node_modules/x/i.js"
  echo '{}' > "$T/.opencode/package.json"; echo x > "$T/.opencode/bun.lock"; echo x > "$T/.opencode/package-lock.json"; echo '*' > "$T/.opencode/.gitignore"
  clean
}
@test "git hooks and local git settings that run commands count as local changes (A5)" {
  hooks="$(git -C "$T" rev-parse --path-format=absolute --git-path hooks)"
  printf '#!/bin/sh\n' > "$hooks/post-checkout"; warned "local changes"; rm "$hooks/post-checkout"
  for kv in core.hooksPath=reports/h hook.x.command=/tmp/x filter.x.clean=cat core.sshCommand=/tmp/x core.fsmonitor=/tmp/x remote.origin.uploadpack=/tmp/x; do
    git -C "$T" config "${kv%%=*}" "${kv#*=}"; warned "local changes"; git -C "$T" config --unset "${kv%%=*}"
  done
  echo '* filter=x' > "$(git -C "$T" rev-parse --path-format=absolute --git-path info/attributes)"; warned "local changes"
}
@test "a local core.worktree or core.bare, which points git at other files, counts as a local change" {
  P="$BATS_TEST_TMPDIR/pristine"; git clone -q --no-local "$T" "$P"  # not a file copy, which git's background maintenance in $T can break
  mkdir -p "$T/.claude"; echo '{}' > "$T/.claude/settings.local.json"
  git -C "$T" config core.worktree "$P"; warned "local changes"; git -C "$T" config --unset core.worktree
  rm "$T/.claude/settings.local.json"; clean
  git -C "$T" config core.bare true; warned "local changes"
}

@test "a hook folder in the person's own git config is theirs, not a change to the copy" {
  mkdir -p "$HOME/hooks"; printf '#!/bin/sh\n' > "$HOME/hooks/post-checkout"; chmod +x "$HOME/hooks/post-checkout"
  git config --global core.hooksPath "$HOME/hooks"
  clean
}
@test "a release older than one this Mac ran warns (A11)" {
  echo next >> "$T/controls/controls.json"; commit "$T"; sign_release "$T" v0.2.0
  clean; [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.2.0 ]
  git -C "$T" checkout -q --detach v0.1.0
  start; [[ "$msg" == *"WARNING"*"v0.1.0, older than v0.2.0"* ]]
  [ "$(cat "$HOME/.config/fortkeep/highest-release")" = v0.2.0 ]
}
@test "Claude Code in bypass, auto or accept-edits mode is warned about at session start (A4)" {
  for m in bypassPermissions acceptEdits auto; do
    run "$H/session-start.sh" <<<"{\"hook_event_name\":\"SessionStart\",\"permission_mode\":\"$m\"}"
    [[ "$(jq -r .systemMessage <<<"$output")" == *"WARNING"*"$m"*"fixes are refused"* ]]
  done
  run "$H/session-start.sh" <<<'{"hook_event_name":"SessionStart","permission_mode":"default"}'
  [[ "$(jq -r .systemMessage <<<"$output")" != *WARNING* ]]
}
@test "a development session says so, names the marker it found, and points to CONTRIBUTING.md instead of /posture" {
  export FORTKEEP_DEV=1
  start
  [[ "$msg" == *"development session"* ]]; [[ "$msg" == *"~/.config/fortkeep/dev is present"* ]]
  [[ "$msg" == *CONTRIBUTING.md* ]]; [[ "$msg" != *"/posture"* ]]
}
@test "FORTKEEP_DEV=1 without the marker ~/.config/fortkeep/dev is a person's session: a fix needs a signed release (A14)" {
  export FORTKEEP_DEV=1; rm "$HOME/.config/fortkeep/dev"
  start; [[ "$msg" != "fortkeep development session"* ]]; [[ "$msg" == *"/posture"* ]]; [[ "$msg" == *"~/.config/fortkeep/dev, which is missing"* ]]
  echo '# x' >> "$T/checks/lib/common.sh"
  mkdir -p "$T/reports/.approvals"; date +%s > "$T/reports/.approvals/BL-RC-01.apply"
  run /bin/bash "$T/fixes/macos/BL-RC-01.sh" apply; [ "$status" -eq 4 ]; [[ "$output" == *"not exactly a signed release"* ]]
  : > "$HOME/.config/fortkeep/dev"; date +%s > "$T/reports/.approvals/BL-RC-01.apply"
  run /bin/bash "$T/fixes/macos/BL-RC-01.sh" apply; [ "$status" -eq 0 ]
}
@test "the marker counts from the account's own home outside the suite, and only from the test's HOME inside it (A14)" {
  . "$REPO/checks/lib/mode.sh"
  export FORTKEEP_DEV=1
  fortkeep_dev_session
  rm "$HOME/.config/fortkeep/dev"; ! fortkeep_dev_session   # whatever the real home holds
  : > "$HOME/.config/fortkeep/dev"
  want=1; [ -f "$(/usr/bin/perl -e 'print +(getpwuid($<))[7]')/.config/fortkeep/dev" ] && want=0
  run env -u BATS_TEST_TMPDIR /bin/bash -c '. "$1"; fortkeep_dev_session' _ "$REPO/checks/lib/mode.sh"; [ "$status" -eq "$want" ]
  unset FORTKEEP_DEV; ! fortkeep_dev_session
}
@test "the test-suite switch can't be faked from a folder an agent in a person's session may write (A14)" {
  . "$REPO/checks/lib/mode.sh"
  fake() {  # DIR — that folder poses as a test's: the suite's marker, a HOME below it, and the development marker
    mkdir -p "$1/home/.config/fortkeep"; : > "$1/.fortkeep-test"; : > "$1/home/.config/fortkeep/dev"
    BATS_TEST_TMPDIR="$1" HOME="$1/home" FORTKEEP_DEV=1 /bin/bash -c '. "$1"; fortkeep_under_test || fortkeep_dev_session' _ "$REPO/checks/lib/mode.sh"
  }
  run fake "$BATS_TEST_TMPDIR/ccd/plans/x"; [ "$status" -ne 0 ]       # a plan folder
  mkdir -p "/private/tmp/claude-$(id -u)"; S="$(mktemp -d "/private/tmp/claude-$(id -u)/fortkeep-test.XXXXXX")"  # agents' scratch
  run fake "$S/scratch"; rc=$status; rm -rf "$S"; [ "$rc" -ne 0 ]
  run fake "$BATS_TEST_TMPDIR/ok"; [ "$status" -eq 0 ]
}
@test "A22: the test-suite switch needs bats as an ancestor, so a folder no list names still can't fake it" {
  . "$REPO/checks/lib/mode.sh"
  F="$BATS_TEST_TMPDIR/anywhere"; mkdir -p "$F/home/.config/fortkeep"; : > "$F/.fortkeep-test"; : > "$F/home/.config/fortkeep/dev"
  check='. "$1"; fortkeep_under_test; echo $? > "$2"'
  BATS_TEST_TMPDIR="$F" HOME="$F/home" run /bin/bash -c "$check" _ "$REPO/checks/lib/mode.sh" "$BATS_TEST_TMPDIR/rc-child"
  [ "$(cat "$BATS_TEST_TMPDIR/rc-child")" = 0 ]   # under bats
  # The same, but detached from bats: its parent exits first, so it is no longer below the test runner.
  ( BATS_TEST_TMPDIR="$F" HOME="$F/home" /bin/bash -c 'while [ "$(/bin/ps -o ppid= -p $$ | tr -d " ")" != 1 ]; do sleep 0.1; done; '"$check" \
      _ "$REPO/checks/lib/mode.sh" "$BATS_TEST_TMPDIR/rc-detached" </dev/null >/dev/null 2>&1 & )
  for _ in $(seq 100); do [ -s "$BATS_TEST_TMPDIR/rc-detached" ] && break; sleep 0.1; done
  [ "$(cat "$BATS_TEST_TMPDIR/rc-detached")" = 1 ]
}

# The fix library and the scripts a person runs refuse a copy that isn't exactly a signed release.
@test "a fix runs on a signed release, and is refused once the copy has local changes" {
  mkdir -p "$T/reports/.approvals"
  date +%s > "$T/reports/.approvals/BL-RC-01.apply"
  run /bin/bash "$T/fixes/macos/BL-RC-01.sh" apply; [ "$status" -eq 0 ]
  echo '# x' >> "$T/checks/lib/common.sh"
  date +%s > "$T/reports/.approvals/BL-RC-01.undo"
  run /bin/bash "$T/fixes/macos/BL-RC-01.sh" undo; [ "$status" -eq 4 ]; [[ "$output" == *"not exactly a signed release"* ]]
}
@test "the scripts a person runs refuse a copy that isn't a signed release, before sourcing anything else" {
  echo 'touch "$BATS_TEST_TMPDIR/sourced"' >> "$T/checks/lib/common.sh"
  run /bin/bash "$T/checks/baseline.sh" accept </dev/null; [ "$status" -eq 4 ]; [[ "$output" == *"signed release"* ]]
  run /bin/bash "$T/checks/private.sh" remove "~/x"; [ "$status" -eq 4 ]; [[ "$output" == *"signed release"* ]]
  run /bin/bash "$T/checks/managed-settings.sh"; [ "$status" -eq 4 ]; [[ "$output" == *"signed release"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/sourced" ]
}
@test "managed-settings.sh prints the root-owned files from the verified release (A10)" {
  mkdir -p "$HOME/.claude"
  FORTKEEP_CLAUDE_DIRS="$HOME/.claude" run /bin/bash "$T/checks/managed-settings.sh"; [ "$status" -eq 0 ]
  [ "$(jq -S .permissions <<<"$output")" = "$(jq -S .permissions "$REPO/templates/managed-settings.json")" ]
  run /bin/bash "$T/checks/managed-settings.sh" guard; [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$REPO/templates/agent-guard.sh")" ]
}
