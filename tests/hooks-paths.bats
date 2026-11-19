load helpers

setup() { setup_env; export CLAUDE_PROJECT_DIR="$REPO"; }
H="$BATS_TEST_DIRNAME/../.claude/hooks"
guard() { "$H/private-guard.sh"; }

@test "private-guard allows prose that names the list file in content" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS")"
  run bash -c "jq -cn --arg f \"$f\" '{tool_name:\"Write\",tool_input:{file_path:\"docs/x.md\",content:(\"see \"+\$f+\" for details\")}}' | '$H/private-guard.sh'"
  [ "$status" -eq 0 ]
}
@test "private-guard blocks an Edit whose file_path is the list file" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS")"
  run bash -c "jq -cn --arg f \"$f\" '{tool_name:\"Edit\",tool_input:{file_path:\$f,old_string:\"a\",new_string:\"b\"}}' | '$H/private-guard.sh'"
  [ "$status" -eq 2 ]
}
@test "private-guard blocks a Glob pattern and a Bash command naming the list file" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS")"
  run bash -c "jq -cn --arg f \"$f\" '{tool_name:\"Glob\",tool_input:{pattern:(\"**/\"+\$f)}}' | '$H/private-guard.sh'"
  [ "$status" -eq 2 ]
  run bash -c "jq -cn --arg f \"$f\" '{tool_name:\"Bash\",tool_input:{command:(\"cat \"+\$f)}}' | '$H/private-guard.sh'"
  [ "$status" -eq 2 ]
}
@test "private-guard still allows the .example sibling as a path" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS")"
  run bash -c "jq -cn --arg f \"$f.example\" '{tool_name:\"Read\",tool_input:{file_path:\$f}}' | '$H/private-guard.sh'"
  [ "$status" -eq 0 ]
}
@test "private-guard still blocks the list file early in a very long command" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS")"
  filler="$(head -c 200000 /dev/zero | tr '\0' 'a' | fold -w 100)"
  jq -cn --arg c "cat $f"$'\n'"$filler" '{tool_name:"Bash",tool_input:{command:$c}}' > "$BATS_TEST_TMPDIR/big.json"
  run "$H/private-guard.sh" < "$BATS_TEST_TMPDIR/big.json"
  [ "$status" -eq 2 ]
}

pg() { jq -cn --arg c "$1" --arg w "${2:-$HOME/Open}" '{tool_name:"Bash", cwd:$w, tool_input:{command:$c}}' | "$H/private-guard.sh"; }
pread() { jq -cn --arg p "$1" --arg w "$2" '{tool_name:"Read", cwd:$w, tool_input:{file_path:$p}}' | "$H/private-guard.sh"; }

@test "private-guard sees through quotes around \$HOME and ~" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg 'cat "$HOME"/Secret/a'; [ "$status" -eq 2 ]
  run pg 'ls ~"/Secret"'; [ "$status" -eq 2 ]
}
@test "private-guard resolves relative paths against the working folder" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg 'cat ../Secret/a' "$HOME/Open"; [ "$status" -eq 2 ]
  run pread '../Secret/a' "$HOME/Open"; [ "$status" -eq 2 ]
  run pg 'cat ../Open/a' "$HOME/Open"; [ "$status" -eq 0 ]
}
@test "private-guard blocks listings and searches rooted above a private folder" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg 'ls ~'; [ "$status" -eq 2 ]
  run pg 'find $HOME -name x'; [ "$status" -eq 2 ]
  run pg 'du -sh ~/*'; [ "$status" -eq 2 ]
  run pg 'ls /'; [ "$status" -eq 2 ]
  run pg 'grep -r token .' "$HOME"; [ "$status" -eq 2 ]
  run pg 'cd ~ && git status'; [ "$status" -eq 0 ]
  run pg 'ls ~/Open'; [ "$status" -eq 0 ]
  run pg 'grep -r token .' "$HOME/Open"; [ "$status" -eq 0 ]
}
pgrep_tool() { jq -cn --arg w "$1" '{tool_name:"Grep", cwd:$w, tool_input:{pattern:"x"}}' | "$H/private-guard.sh"; }

@test "private-guard treats a search with no path as rooted at the working folder" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg 'rg token' "$HOME"; [ "$status" -eq 2 ]
  run pg 'grep -r token' "$HOME"; [ "$status" -eq 2 ]
  run pg 'find -name x' "$HOME"; [ "$status" -eq 2 ]
  run pgrep_tool "$HOME"; [ "$status" -eq 2 ]
  run pg 'rg token' "$HOME/Open"; [ "$status" -eq 0 ]
  run pgrep_tool "$HOME/Open"; [ "$status" -eq 0 ]
  run bash -c "jq -cn '{tool_name:\"Grep\",tool_input:{pattern:\"x\"}}' | '$H/private-guard.sh'"
  [ "$status" -eq 0 ]
}
@test "private-guard roots search tools with option values or quoted patterns at the working folder" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg "rg -g '*.md' token" "$HOME"; [ "$status" -eq 2 ]
  run pg 'grep -r "api key"' "$HOME"; [ "$status" -eq 2 ]
  run pg 'rg -A 3 token' "$HOME"; [ "$status" -eq 2 ]
  run pg 'rg --type md token' "$HOME"; [ "$status" -eq 2 ]
  run pg 'rg token ~/Open' "$HOME"; [ "$status" -eq 0 ]
  run pg 'grep -r "api key" ~/Open' "$HOME"; [ "$status" -eq 0 ]
  run pg "rg -g '*.md' token ./Open" "$HOME"; [ "$status" -eq 0 ]
  run pg 'rg token' "$HOME/Open"; [ "$status" -eq 0 ]
}
@test "private-guard follows cd inside a command" {
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  run pg 'cd ~ && find . -name x' "$HOME/Open"; [ "$status" -eq 2 ]
  run pg 'cd ~ && cat Secret/a' "$HOME/Open"; [ "$status" -eq 2 ]
  run pg 'cd ~/Open && ls' "$HOME"; [ "$status" -eq 0 ]
  run pg 'cd ~/Open && ls'; [ "$status" -eq 0 ]
  run pg 'cd ~ && git status'; [ "$status" -eq 0 ]
}
@test "the list file name and the approvals folder match in any letter case" {
  f="$(basename "$DEVWARD_PRIVATE_PATHS" | tr '[:lower:]' '[:upper:]')"
  run bash -c "jq -cn --arg f \"$f\" '{tool_name:\"Read\",tool_input:{file_path:\$f}}' | '$H/private-guard.sh'"
  [ "$status" -eq 2 ]
  run bash -c "jq -cn --arg c \"cat $f\" '{tool_name:\"Bash\",tool_input:{command:\$c}}' | '$H/bash-guard.sh'"
  [ "$status" -eq 2 ]
  run bash -c "jq -cn '{tool_name:\"Bash\",tool_input:{command:\"ls reports/.APPROVALS\"}}' | '$H/bash-guard.sh'"
  [ "$status" -eq 2 ]
}
