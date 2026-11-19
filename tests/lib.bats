load helpers

setup() { setup_env; . "$REPO/checks/lib/common.sh"; }

@test "devward_result prints one JSON object" {
  run devward_result BL-OS-01 PASS "FileVault: On"
  [ "$status" -eq 0 ]
  [ "$(field id)" = BL-OS-01 ]
  [ "$(field status)" = PASS ]
  [ "$(field evidence)" = "FileVault: On" ]
  [ "$(field note)" = "" ]
}

@test "devward_result rejects an unknown status" {
  run devward_result BL-OS-01 MAYBE ""
  [ "$status" -eq 2 ]
}

@test "devward_tilde shortens home paths" {
  run devward_tilde "$HOME/Library/x"
  [ "$output" = "~/Library/x" ]
  run devward_tilde /etc/hosts
  [ "$output" = /etc/hosts ]
}

@test "devward_path prefixes the sysroot" {
  run devward_path /etc/pam.d/sudo_local
  [ "$output" = "$DEVWARD_SYSROOT/etc/pam.d/sudo_local" ]
}

@test "private paths expand ~ and ignore comments" {
  printf '# comment\n~/Secret/\n\n/opt/other\n' > "$DEVWARD_PRIVATE_PATHS"
  run devward_private_list
  [ "${lines[0]}" = "$HOME/Secret" ]
  [ "${lines[1]}" = /opt/other ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "devward_is_private matches the folder and below, not siblings" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  devward_is_private "$HOME/Secret"
  devward_is_private "$HOME/Secret/a/b"
  run devward_is_private "$HOME/SecretNot"
  [ "$status" -eq 1 ]
}

@test "devward_walk never lists inside a private folder" {
  mkdir -p "$HOME/Secret/inner" "$HOME/Open"
  touch "$HOME/Secret/inner/key.pem" "$HOME/Open/key.pem"
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run devward_walk "$HOME" -type f -name '*.pem'
  [ "$output" = "$HOME/Open/key.pem" ]
}

@test "devward_timeout kills a slow command and its children quickly" {
  start=$(date +%s)
  run devward_timeout 1 /bin/bash -c 'sleep 10 & sleep 10'
  [ "$status" -eq 142 ]
  [ $(( $(date +%s) - start )) -lt 4 ]
}

@test "devward_timeout stops a command that ignores TERM" {
  start=$(date +%s)
  run devward_timeout 1 bash -c "trap '' TERM; sleep 5"
  [ "$status" -eq 142 ]
  [ $(( $(date +%s) - start )) -lt 3 ]
}

@test "devward_timeout: the timed-out shell itself never runs on (macOS's group KILL can miss it)" {
  # The miss is a race, so try several times; before the fix about one run in three printed "survived".
  for i in 1 2 3 4 5 6 7 8; do
    o="$(devward_timeout 1 /bin/bash -c 'sleep 3; echo survived' 2>/dev/null)" || true
    [ -z "$o" ]
  done
}
@test "devward_timeout returns at once when the command leaves a background job holding the output" {
  start=$(date +%s)
  run devward_timeout 5 sh -c 'sleep 30 & echo x'
  [ "$status" -eq 0 ]; [ "$output" = x ]
  [ $(( $(date +%s) - start )) -lt 4 ]
}

@test "devward_timeout passes through a normal exit code" {
  run devward_timeout 5 /bin/bash -c 'echo hi; exit 3'
  [ "$status" -eq 3 ]
  [ "$output" = hi ]
}

@test "devward_timeout gives 128+N for a command a signal stopped, and keeps 142 for its own timeout" {
  run devward_timeout 5 /bin/bash -c 'kill -KILL $$'; [ "$status" -eq 137 ]
  run devward_timeout 5 /bin/bash -c 'kill -TERM $$'; [ "$status" -eq 143 ]
  run devward_timeout 5 /bin/bash -c 'kill -ALRM $$'; [ "$status" -eq 255 ]
  [ "$(devward_signal_name 137)" = KILL ]
  run devward_signal_name 142; [ "$status" -eq 1 ]
  run devward_signal_name 3; [ "$status" -eq 1 ]
}

@test "devward_walk prunes a private folder whose name has [ ] * ? or \\ in it" {
  for n in 'Client [NDA]' 'Star*' 'Q?' 'Back\slash'; do mkdir -p "$HOME/$n"; touch "$HOME/$n/a.pem"; printf '%s\n' "$HOME/$n" >> "$DEVWARD_PRIVATE_PATHS"; done
  mkdir -p "$HOME/Client N"; touch "$HOME/Client N/b.pem"   # [NDA] as a pattern would match this one instead
  run devward_walk "$HOME" -type f -name '*.pem'
  [ "$output" = "$HOME/Client N/b.pem" ]
}
@test "devward_defaults_unset knows each macOS wording for a key or domain never set, and nothing else" {
  devward_defaults_unset "The domain/default pair of (com.x, k) does not exist"
  devward_defaults_unset "Could not find key k"
  devward_defaults_unset "Error: Domain 'com.apple.controlcenter' not found."
  ! devward_defaults_unset "Could not read /Library/Preferences/x.plist: permission denied"
}
@test "devward_walk works with no private paths" {
  mkdir -p "$HOME/Open"; touch "$HOME/Open/a.pem"
  run devward_walk "$HOME" -type f -name '*.pem'
  [ "$output" = "$HOME/Open/a.pem" ]
}

@test "devward_real_cmd skips Safe Chain shims" {
  . "$REPO/checks/lib/common.sh"
  mkdir -p "$HOME/.safe-chain/shims"
  printf '#!/bin/sh\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
  stub npm 'exit 0'
  DEVWARD_USER_PATH="$HOME/.safe-chain/shims:$BATS_TEST_TMPDIR/bin" run devward_real_cmd npm
  [ "$status" -eq 0 ]; [ "$output" = "$BATS_TEST_TMPDIR/bin/npm" ]
  run devward_real_cmd no-such-tool-here; [ "$status" -eq 1 ]
}
@test "devward_version_ge compares dotted versions" {
  . "$REPO/checks/lib/common.sh"
  devward_version_ge 2.56.0 2.54
  devward_version_ge 2.54 2.54
  run devward_version_ge 2.50.1 2.54; [ "$status" -eq 1 ]
  devward_version_ge 3 2.54.9
}
@test "devward_shell_probe reads the right start-up files for each shell type" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/shells.sh"
  echo 'export A=env' > "$HOME/.zshenv"
  echo 'export B=login' > "$HOME/.zlogin"
  echo 'export C=bashlogin' > "$HOME/.bash_profile"
  [ "$(devward_shell_probe zsh 'echo $A$B')" = env ]
  [ "$(devward_shell_probe zsh-login 'echo $A$B')" = envlogin ]
  [ "$(X=1 devward_shell_probe clean-zsh-login 'echo $A$X')" = env ]
  [ "$(devward_shell_probe bash-login 'echo $C')" = bashlogin ]
  [ "$(devward_shell_probe bash 'echo $A$C')" = env ]
  echo 'export D=rc' > "$HOME/.zshrc"
  [ "$(devward_shell_probe zsh-interactive 'echo $A$D $TERM')" = "envrc dumb" ]
  run devward_shell_probe nonsense 'echo x'; [ "$status" -eq 2 ]
}
@test "devward_shell_probe times out and closes stdin" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/shells.sh"
  DEVWARD_SHELL_TIMEOUT=1 run devward_shell_probe zsh 'sleep 5'
  [ "$status" -eq 142 ]
  [ "$(echo hi | devward_shell_probe zsh 'cat; echo done')" = done ]
}
@test "devward_shell_types adds bash only when bash start-up files exist" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/shells.sh"
  [ "$(devward_shell_types | wc -l | tr -d ' ')" = 4 ]
  touch "$HOME/.bashrc"
  [ "$(devward_shell_types | wc -l | tr -d ' ')" = 6 ]
}
@test "devward_claude_dirs lists each existing config folder once; DEVWARD_CLAUDE_DIRS replaces them" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$HOME/.claude" "$BATS_TEST_TMPDIR/ccd"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd" run devward_claude_dirs
  [ "${#lines[@]}" -eq 2 ]
  CLAUDE_CONFIG_DIR="$HOME/.claude" run devward_claude_dirs
  [ "${#lines[@]}" -eq 1 ]
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/ccd:$BATS_TEST_TMPDIR/none" run devward_claude_dirs
  [ "${#lines[@]}" -eq 1 ]; [[ "$output" == */ccd ]]
}
@test "devward_claude_states finds ~/.claude.json and per-folder state files" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$BATS_TEST_TMPDIR/ccd"; echo '{}' > "$HOME/.claude.json"; echo '{}' > "$BATS_TEST_TMPDIR/ccd/.claude.json"
  DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/ccd" run devward_claude_states
  [ "${#lines[@]}" -eq 2 ]
}
@test "an ERROR always has evidence: an empty one takes the note, or a default" {
  run devward_result X ERROR "" "netstat gave no output"
  [ "$(field evidence)" = "netstat gave no output" ]; [ "$(field note)" = "" ]
  run devward_result X ERROR ""; [ -n "$(field evidence)" ]
  run devward_result X FAIL "" "n"; [ "$(field evidence)" = "" ]
}
@test "no check and not the runner writes an ERROR with empty evidence" {
  run grep -n 'ERROR ""' "$REPO"/checks/*.sh "$REPO"/checks/macos/*.sh; [ "$status" -eq 1 ]
}
@test "every check and fix script is executable" {
  for f in "$REPO"/checks/*.sh "$REPO"/checks/macos/*.sh "$REPO"/fixes/macos/*.sh; do [ -x "$f" ] || { echo "not executable: $f"; false; }; done
}

@test "devward_claude_dirs also lists each aimux profile Claude has used, once, and ignores other folders" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  P="$HOME/.aimux/profiles"; mkdir -p "$HOME/.claude" "$P/work/projects" "$P/home" "$P/empty" "$P/notes"
  echo '{}' > "$P/home/settings.json"; echo x > "$P/notes/readme.txt"
  Pp="$(cd "$P" && pwd -P)"
  run devward_claude_dirs
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"$Pp/work"* ]]; [[ "$output" == *"$Pp/home"* ]]; [[ "$output" != *empty* ]]; [[ "$output" != *notes* ]]
  CLAUDE_CONFIG_DIR="$P/work" run devward_claude_dirs
  [ "${#lines[@]}" -eq 3 ]
  ln -s "$P/home" "$BATS_TEST_TMPDIR/home-link"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/home-link" run devward_claude_dirs
  [ "${#lines[@]}" -eq 3 ]
  DEVWARD_CLAUDE_DIRS="$HOME/.claude" run devward_claude_dirs
  [ "${#lines[@]}" -eq 1 ]
  echo "$P/home" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs
  [ "${#lines[@]}" -eq 2 ]; [[ "$output" != *"$Pp/home"* ]]
}

@test "devward_claude_dirs skips a private profile whose entry is spelled as the physical path under a symlinked HOME" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$HOME/.claude" "$HOME/.aimux/profiles/home"; echo '{}' > "$HOME/.aimux/profiles/home/settings.json"
  Hp="$(cd "$HOME" && pwd -P)"; ln -s "$Hp" "$BATS_TEST_TMPDIR/hlink"
  echo "$Hp/.aimux/profiles/home" > "$DEVWARD_PRIVATE_PATHS"
  HOME="$BATS_TEST_TMPDIR/hlink" run devward_claude_dirs
  [ "${#lines[@]}" -eq 1 ]; [[ "$output" != *profiles/home* ]]
}
@test "devward_claude_dirs skips a private profile reached through a symlink, either way round" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$HOME/.claude" "$HOME/.aimux/profiles" "$BATS_TEST_TMPDIR/real"; echo '{}' > "$BATS_TEST_TMPDIR/real/settings.json"
  ln -s "$BATS_TEST_TMPDIR/real" "$HOME/.aimux/profiles/lk"
  echo "$BATS_TEST_TMPDIR/real" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
  echo "$HOME/.aimux/profiles/lk" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
  echo "$BATS_TEST_TMPDIR/real" > "$DEVWARD_PRIVATE_PATHS"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/real" run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
}
@test "devward_claude_dirs skips a private profile whose entry has // or /./ in it" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  P="$HOME/.aimux/profiles"; mkdir -p "$HOME/.claude" "$P/home"; echo '{}' > "$P/home/settings.json"
  printf '%s\n' "$P/home//" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
  printf '%s\n' "$P/./home/." > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
  : > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_dirs; [ "${#lines[@]}" -eq 2 ]
}

@test "devward_claude_private_skipped: true for a private ~/.claude, false when nothing is private" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$HOME/.claude"
  run devward_claude_private_skipped; [ "$status" -ne 0 ]
  echo "$HOME/.claude" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_private_skipped; [ "$status" -eq 0 ]
  run devward_claude_dirs; [ -z "$output" ]
}
@test "devward_claude_private_skipped: a private aimux profiles folder is skipped whole, and counts" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  P="$HOME/.aimux/profiles"; mkdir -p "$HOME/.claude" "$P/work"; echo '{}' > "$P/work/settings.json"
  echo "$P" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_private_skipped; [ "$status" -eq 0 ]
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]; [[ "$output" != *work* ]]
  echo "$HOME/.aimux" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_private_skipped; [ "$status" -eq 0 ]
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]
}
@test "devward_claude_private_skipped works with the DEVWARD_CLAUDE_DIRS override" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  mkdir -p "$BATS_TEST_TMPDIR/ccd" "$BATS_TEST_TMPDIR/sec"
  export DEVWARD_CLAUDE_DIRS="$BATS_TEST_TMPDIR/ccd:$BATS_TEST_TMPDIR/sec"
  run devward_claude_private_skipped; [ "$status" -ne 0 ]
  echo "$BATS_TEST_TMPDIR/sec" > "$DEVWARD_PRIVATE_PATHS"
  run devward_claude_private_skipped; [ "$status" -eq 0 ]
  run devward_claude_dirs; [ "${#lines[@]}" -eq 1 ]; [[ "$output" == */ccd ]]
}
@test "devward_hook_script skips VAR=value words, env and its options, and an interpreter and its options" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  g="$HOME/.claude/hooks/guard.sh"; mkdir -p "${g%/*}"; : > "$g"
  for c in "$g" "~/.claude/hooks/guard.sh" "\"\$HOME\"/.claude/hooks/guard.sh" "bash -e $g" "/usr/bin/python3 -I $g || exit 2" \
    "A=1 B_2=x $g" "FOO=1 /bin/zsh $g" "env $g" "/usr/bin/env -i -u PATH -P /bin A=1 bash $g" "X=1 env -S bash $g"; do
    [ "$(devward_hook_script "$c")" = "$g" ] || { echo "not found in: $c"; false; }
  done
  for c in "echo $g" "a-b=1 $g" "env -u $g"; do
    [ -z "$(devward_hook_script "$c")" ] || { echo "found in: $c"; false; }
  done
}
@test "devward_hook_scripts lists each script once, for the named tools' PreToolUse hooks or every event's; unreadable → non-zero" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"
  for n in b w s; do : > "$HOME/$n.sh"; done
  jq -n --arg h "$HOME" '{hooks:{PreToolUse:[{matcher:"Bash", hooks:[{type:"command", command:("env X=1 bash " + $h + "/b.sh")}]},
    {matcher:"Write|Edit", hooks:[{type:"command", command:($h + "/w.sh")}, {type:"command", command:("A=1 " + $h + "/b.sh")}]}],
    SessionStart:[{hooks:[{type:"command", command:($h + "/s.sh")}]}]}}' > "$HOME/settings.json"
  [ "$(devward_hook_scripts "$HOME/settings.json" Bash)" = "$HOME/b.sh" ]
  [ "$(devward_hook_scripts "$HOME/settings.json" Bash Write)" = "$HOME/b.sh"$'\n'"$HOME/w.sh" ]
  [ "$(devward_hook_scripts "$HOME/settings.json" | sort)" = "$(printf '%s\n' "$HOME/b.sh" "$HOME/s.sh" "$HOME/w.sh")" ]
  echo '{oops' > "$HOME/settings.json"
  run devward_hook_scripts "$HOME/settings.json"; [ "$status" -ne 0 ]
  run devward_hook_scripts "$HOME/settings.json" Bash; [ "$status" -ne 0 ]
}
@test "devward_join joins non-empty lines with a separator, a space by default; devward_count counts them" {
  [ "$(devward_join $'a\n\nb c\n')" = "a b c" ]
  [ "$(devward_join $'a\n\nb, c' ', ')" = "a, b, c" ]
  [ -z "$(devward_join '')" ]
  [ "$(devward_count $'a\n\nb\n')" = 2 ]; [ "$(devward_count '')" = 0 ]
}
@test "devward_realpath resolves each path in one call, an empty line for one that can't be resolved" {
  mkdir -p "$BATS_TEST_TMPDIR/real dir"; : > "$BATS_TEST_TMPDIR/real dir/f"; ln -s "$BATS_TEST_TMPDIR/real dir/f" "$BATS_TEST_TMPDIR/l"
  P="$(cd "$BATS_TEST_TMPDIR/real dir" && pwd -P)"
  run devward_realpath "$BATS_TEST_TMPDIR/l" "$BATS_TEST_TMPDIR/none/x" "$BATS_TEST_TMPDIR/real dir/f"
  [ "${lines[0]}" = "$P/f" ]; [ "$output" = "$P/f"$'\n\n'"$P/f" ]
}
@test "devward_strip_hash_comments drops # comments and keeps # inside quoted strings" {
  . "$REPO/checks/lib/editors.sh"
  printf '%s\n' 'a = "x # y" # gone' "b = 'p # q' # gone too" '# all gone' 'c = "esc \" # kept"' > "$BATS_TEST_TMPDIR/t"
  [ "$(devward_strip_hash_comments "$BATS_TEST_TMPDIR/t")" = "$(printf '%s\n' 'a = "x # y" ' "b = 'p # q' " '' 'c = "esc \" # kept"')" ]
}
@test "devward_control_hashes marks every unreadable plain file, even when shasum can read none of them" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  . "$REPO/checks/lib/agents.sh"; . "$REPO/checks/lib/baselines.sh"
  A="$BATS_TEST_TMPDIR/a"; Z="$BATS_TEST_TMPDIR/z"; echo a > "$A"; echo z > "$Z"
  h="$(shasum -a 256 "$A" | cut -c1-64)"
  [ "$(printf 'file\t%s\nfile\t%s\n' "$A" "$Z" | devward_control_hashes)" = "$(printf '%s\tfile\t%s\n%s\tfile\t%s' "$A" "$h" "$Z" "$(shasum -a 256 "$Z" | cut -c1-64)")" ]
  chmod 000 "$A" "$Z"
  out="$(printf 'file\t%s\nfile\t%s\n' "$A" "$Z" | devward_control_hashes)"; chmod 644 "$A" "$Z"
  [ "$out" = "$(printf '%s\tfile\tunreadable\n%s\tfile\tunreadable' "$A" "$Z")" ]
}
