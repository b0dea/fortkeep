load helpers

setup() {
  setup_env
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R/docs"
  export CLAUDE_PROJECT_DIR="$R"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd"; mkdir -p "$CLAUDE_CONFIG_DIR/projects/p/memory" "$CLAUDE_CONFIG_DIR/plans"
  export FORTKEEP_DEV=1  # a development session: the repo's own files are editable (the default is reports/ only)
}
W="$BATS_TEST_DIRNAME/../.claude/hooks/write-guard.sh"
edit() { jq -cn --arg p "$1" --arg w "${2:-$R}" '{tool_name:"Edit", cwd:$w, tool_input:{file_path:$p, old_string:"a", new_string:"b"}}' | "$W"; }

@test "edits inside the repo are allowed, relative or absolute, existing or new" {
  run edit "$R/docs/a.md"; [ "$status" -eq 0 ]
  run edit "docs/new/b.md"; [ "$status" -eq 0 ]
}
@test "edits outside the repo are blocked" {
  run edit "$HOME/.zshrc"; [ "$status" -eq 2 ]; [[ "$output" == *"go through fix scripts"* ]]
  run edit "~/.zshrc"; [ "$status" -eq 2 ]
  run edit "../outside.txt"; [ "$status" -eq 2 ]
  run edit "$R/docs/../../outside.txt"; [ "$status" -eq 2 ]
}
@test "a symlink inside the repo cannot lead outside" {
  mkdir -p "$HOME/elsewhere"; ln -s "$HOME/elsewhere" "$R/link"
  run edit "$R/link/x.txt"; [ "$status" -eq 2 ]
}
@test "a symlink leaf is followed: outside, dangling and chained are blocked, inside is allowed" {
  mkdir -p "$HOME/elsewhere"; : > "$HOME/elsewhere/real.txt"
  ln -s "$HOME/elsewhere/real.txt" "$R/rc.txt"
  run edit "$R/rc.txt"; [ "$status" -eq 2 ]
  ln -s "$HOME/elsewhere/nothing.txt" "$R/dangling.txt"
  run edit "$R/dangling.txt"; [ "$status" -eq 2 ]
  ln -s rc.txt "$R/hop1"; ln -s hop1 "$R/hop2"
  run edit "$R/hop2"; [ "$status" -eq 2 ]
  : > "$R/CLAUDE.md"; ln -s CLAUDE.md "$R/AGENTS.md"
  run edit "$R/AGENTS.md"; [ "$status" -eq 0 ]
  ln -s loop2 "$R/loop1"; ln -s loop1 "$R/loop2"
  run edit "$R/loop1"; [ "$status" -eq 2 ]
}
@test "Claude's plan folder, and this repo's scratch and memory, are allowed" {
  enc="$(printf '%s' "$R" | sed 's/[^A-Za-z0-9]/-/g')"  # Claude Code's name for a project's folders
  run edit "/private/tmp/claude-$(id -u)/$enc/s/notes.md"; [ "$status" -eq 0 ]
  run edit "/private/tmp/claude-$(id -u)/-Users-other/s/notes.md"; [ "$status" -eq 2 ]  # another project's scratch
  run edit "$CLAUDE_CONFIG_DIR/projects/$enc/memory/m.md"; [ "$status" -eq 0 ]
  run edit "$CLAUDE_CONFIG_DIR/projects/p/memory/m.md"; [ "$status" -eq 2 ]  # another project's memory
  run edit "$CLAUDE_CONFIG_DIR/plans/x.md"; [ "$status" -eq 0 ]
  run edit "$CLAUDE_CONFIG_DIR/settings.json"; [ "$status" -eq 2 ]
}
@test "Write and NotebookEdit are covered; a call without a path passes; junk fails closed" {
  run bash -c "jq -cn --arg p '$HOME/x' '{tool_name:\"Write\",tool_input:{file_path:\$p,content:\"x\"}}' | '$W'"; [ "$status" -eq 2 ]
  run bash -c "jq -cn --arg p '$HOME/n.ipynb' '{tool_name:\"NotebookEdit\",tool_input:{notebook_path:\$p}}' | '$W'"; [ "$status" -eq 2 ]
  run bash -c "jq -cn '{tool_name:\"Edit\",tool_input:{}}' | '$W'"; [ "$status" -eq 0 ]
  run bash -c "printf 'not json' | '$W'"; [ "$status" -eq 2 ]
}
patch() {  # an apply_patch call (Codex sends it this way; the OpenCode plugin passes patchText the same way)
  jq -cn --arg p "$1" --arg w "${2:-$R}" '{tool_name:"apply_patch", cwd:$w, tool_input:{command:$p}}' | "$W"
}
P() { printf '*** Begin Patch\n%s\n*** End Patch\n' "$1"; }
@test "a patch is checked file by file: add, update, delete and a move's destination" {
  run patch "$(P "$(printf '*** Update File: docs/a.md\n@@\n-a\n+b\n*** Add File: %s/docs/new.md\n+x' "$R")")"; [ "$status" -eq 0 ]
  run patch "$(P "$(printf '*** Update File: docs/a.md\n@@\n-a\n+b\n*** Add File: %s/.zshrc\n+x' "$HOME")")"; [ "$status" -eq 2 ]
  run patch "$(P '*** Delete File: ../outside.txt')"; [ "$status" -eq 2 ]
  run patch "$(P "$(printf '*** Update File: docs/a.md\n*** Move to: %s/.zshrc\n@@\n-a\n+b' "$HOME")")"; [ "$status" -eq 2 ]
}
@test "a patch header indented with Unicode space, as Codex and OpenCode trim it, is still checked" {
  run patch "$(P "$(printf '*** Update File: docs/a.md\n@@\n-a\n+b\n*** Add File: %s/docs/n.md\n+x\n%s*** Add File: %s/.zshrc\n+x' "$R" "$(printf '\xc2\xa0')" "$HOME")")"
  [ "$status" -eq 2 ]
  run patch "$(P "$(printf '*** Add File:%s/.zshrc\n+x' "$HOME")")"; [ "$status" -eq 2 ]
}
@test "A25: Codex 0.170's patch grammar: its end-of-file marker passes, and its environment header, which names no path, is refused" {
  run patch "$(P "$(printf '*** Update File: docs/a.md\n@@\n-a\n+b\n*** End of File')")"; [ "$status" -eq 0 ]
  run patch "$(P "$(printf '*** Environment ID: remote\n*** Update File: docs/a.md\n@@\n-a\n+b')")"; [ "$status" -eq 2 ]
}
@test "a patch whose files can't be read is blocked" {
  run patch "$(P '+just text')"; [ "$status" -eq 2 ]; [[ "$output" == *"could not read"* ]]
}
@test "the approval tokens and KnockKnock scans can't be written by an edit or a patch" {
  run edit "$R/reports/.approvals/BL-RC-01.apply"; [ "$status" -eq 2 ]
  run edit "reports/knockknock/latest.json"; [ "$status" -eq 2 ]
  run patch "$(P '*** Add File: reports/.approvals/BL-RC-01.apply')"; [ "$status" -eq 2 ]
  run patch "$(P '*** Update File: docs/a.md')"; [ "$status" -eq 0 ]
}
@test "a patch's headers count when indented, and an apply_patch without readable files is blocked" {
  run patch "$(printf '  *** Begin Patch\n  *** Add File: %s/.zshrc\n+x\n  *** End Patch' "$HOME")"; [ "$status" -eq 2 ]
  run patch "$(printf '*** Begin Patch\n*** Update File: docs/a.md\n   *** Add File: %s/.zshrc\n+x\n*** End Patch' "$HOME")"; [ "$status" -eq 2 ]
  run patch "just text"; [ "$status" -eq 2 ]
}
@test "outside a development session nothing in the repo is writable, reports/ included" {
  unset FORTKEEP_DEV
  run edit "$R/reports/config.json"; [ "$status" -eq 2 ]; [[ "$output" == *"checks/configure.sh"* ]]
  run edit "$R/reports/latest/results.json"; [ "$status" -eq 2 ]
  run edit "$R/docs/a.md"; [ "$status" -eq 2 ]; [[ "$output" == *"FORTKEEP_DEV=1"* ]]
  run edit "$R/.claude/settings.local.json"; [ "$status" -eq 2 ]
  run patch "$(P '*** Update File: checks/run.sh')"; [ "$status" -eq 2 ]
  run edit "$R/reports/.approvals/BL-RC-01.apply"; [ "$status" -eq 2 ]
}
