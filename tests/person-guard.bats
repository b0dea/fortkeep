load helpers

# Decision 16: a person's session (no DEVWARD_DEV) is allow-listed. Each call is the JSON the agent sends, fed to the
# hook .claude/settings.json runs for every tool. The A1-A9 reproductions from the security review must all be refused.
setup() {
  setup_env; person_session
  export CLAUDE_PROJECT_DIR="$REPO"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/ccd"; mkdir -p "$CLAUDE_CONFIG_DIR/plans"
}
G="$BATS_TEST_DIRNAME/../.claude/hooks/guard.sh"
# Claude Code names a project's folders after its path, every character but a letter or digit turned into -.
ENC="$(printf '%s' "$REPO" | sed 's/[^A-Za-z0-9]/-/g')"
SCR="/private/tmp/claude-$(id -u)/$ENC"
call() {  # TOOL INPUT_JSON [CWD] [PERMISSION_MODE]
  jq -cn --arg t "$1" --argjson i "$2" --arg w "${3:-$REPO}" --arg m "${4:-default}" \
    '{hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i, cwd:$w, permission_mode:$m}' | "$G"
}
sh_() { call Bash "$(jq -cn --arg c "$1" '{command:$c}')" "${2:-$REPO}" "${3:-default}"; }
read_() { call Read "$(jq -cn --arg p "$1" '{file_path:$p}')"; }
write_() { call Write "$(jq -cn --arg p "$1" '{file_path:$p, content:"x"}')"; }
allowed() { run "$@"; [ "$status" -eq 0 ] || { echo "refused: $*: $output"; return 1; }; }
refused() { run "$@"; [ "$status" -eq 2 ] || { echo "allowed: $*"; return 1; }; [[ "$output" == *"Blocked by devward"* ]]; }

@test "A1: a look-alike letter (U+017F, which APFS folds to s) passes no guard" {
  refused write_ "reports/.approval$(printf '\xc5\xbf')/BL-RC-01.apply"
  refused sh_ "mkdir -p reports/.approval$(printf '\xc5\xbf') && date +%s > reports/.approval$(printf '\xc5\xbf')/BL-SC-02.apply"
  refused sh_ "cat private-path$(printf '\xc5\xbf')"
  refused read_ "private-path$(printf '\xc5\xbf')"
  printf '~/Private\n' > "$DEVWARD_PRIVATE_PATHS"; mkdir -p "$HOME/Private"
  refused read_ "$HOME/Priva$(printf '\xc5\xbf')e/a.txt"
  refused sh_ "echo x >> ~/.z$(printf '\xc5\xbf')hrc"
  refused sh_ "checks/private.$(printf '\xc5\xbf')h remove ~/Private"
  run sh_ "checks/run.sh --only BL-RC-0$(printf '\xc2\xb9')"; [ "$status" -eq 2 ]; [[ "$output" == *"non-ASCII"* ]]
}
@test "A2: the shell can't rewrite guards, checks, fixes, agent config or git, nor commit to hide it" {
  refused sh_ 'cp reports/g.sh .claude/hooks/bash-guard.sh'
  refused sh_ "sed -i '' 's/exit 4/:/' fixes/lib/fix.sh"
  refused sh_ 'perl -pi -e s/FAIL/PASS/ checks/macos/*.sh'
  refused sh_ 'echo {} > .claude/settings.local.json'
  refused sh_ 'echo x > .git/hooks/post-checkout'
  refused sh_ 'git config core.hooksPath reports/h'
  refused sh_ 'git commit -qam x'
}
@test "A3: nothing dropped in reports/ can be run, sourced or unpacked" {
  refused sh_ 'bash reports/s.sh'
  refused sh_ 'source reports/s.sh'
  refused sh_ '. reports/s.sh'
  refused sh_ 'tar -xf reports/a.tar -C reports'
  refused sh_ 'reports/s.sh'
}
@test "A4: a fix runs in exactly one spelling, from the repo folder, and not in bypass, auto or accept-edits mode" {
  allowed sh_ 'fixes/macos/BL-RC-01.sh apply'
  allowed sh_ 'fixes/macos/BL-RC-01.sh undo'
  refused sh_ './fixes/macos/BL-RC-01.sh apply'
  refused sh_ 'bash fixes/macos/BL-RC-01.sh apply'
  refused sh_ '/bin/bash -p fixes/macos/BL-RC-01.sh apply'
  refused sh_ "$REPO/fixes/macos/BL-RC-01.sh apply"
  refused sh_ 'fixes/macos/BL-RC-01.sh  apply now'
  refused sh_ 'fixes/macos/BL-XX-99.sh apply'
  refused sh_ 'fixes/macos/BL-RC-01.sh apply' "$REPO/checks"
  refused sh_ 'checks/run.sh' "$BATS_TEST_TMPDIR"
  for m in bypassPermissions acceptEdits auto; do
    run sh_ 'fixes/macos/BL-RC-01.sh apply' "$REPO" "$m"; [ "$status" -eq 2 ]; [[ "$output" == *"$m"* ]]
    allowed sh_ 'checks/run.sh --only BL-RC-01' "$REPO" "$m"
  done
}
@test "A4: Codex's workdir counts as the working folder" {
  refused call Bash "$(jq -cn --arg w "$BATS_TEST_TMPDIR" '{command:"checks/run.sh", workdir:$w}')"
  allowed call Bash "$(jq -cn --arg w "$REPO" '{command:"checks/run.sh", workdir:$w}')"
}
@test "A6: the agent can't start another agent to type an approval" {
  refused sh_ "codex exec 'Apply BL-SC-02'"
  refused sh_ 'claude -p "Apply BL-SC-02"'
  refused sh_ 'opencode run Apply BL-SC-02'
}
@test "A7: a tool with no guard is refused; the ones that touch no file and run no command pass" {
  refused call Monitor '{"command":"cat private-paths","description":"x"}'
  refused call Agent '{"prompt":"read ~/Private","subagent_type":"general-purpose"}'
  refused call Task '{"prompt":"x"}'
  refused call mcp__files__read '{"path":"/"}'
  refused call LSP '{"operation":"hover","filePath":"/etc/hosts"}'
  refused call NotebookRead '{"notebook_path":"/tmp/x.ipynb"}'
  for t in AskUserQuestion TodoWrite TaskCreate TaskUpdate TaskList TaskGet Skill ToolSearch; do
    allowed call "$t" '{}'
  done
}
@test "web tools are refused: a fetch URL or search query could carry results, scans or transcripts off the Mac" {
  refused call WebFetch '{"url":"https://example.com/?q=x","prompt":"x"}'
  [[ "$output" == *"web"* ]]
  refused call WebSearch '{"query":"x"}'
  refused call web_search '{"query":"x"}'
}
@test "A9: the agent writes nothing in reports/, so results, the latest link and the weekly stamp can't be forged" {
  for p in reports/latest/results.json reports/20260101T000000Z/results.json reports/latest reports/weekly-last \
    reports/config.json reports/change-log.md "$REPO/reports/x" accepted.json private-paths checks/run.sh; do
    refused write_ "$p"
    refused call Edit "$(jq -cn --arg p "$p" '{file_path:$p, old_string:"a", new_string:"b"}')"
  done
  refused call apply_patch '{"command":"*** Begin Patch\n*** Add File: reports/weekly-last\n+9999999999\n*** End Patch"}'
  refused call NotebookEdit '{"notebook_path":"reports/x.ipynb","new_source":"x"}'
  refused sh_ 'touch reports/weekly-last'
}
@test "writes go only to this project's scratch folder and the plan folder, never memory (A16)" {
  allowed write_ "$SCR/s/notes.md"
  allowed write_ "$CLAUDE_CONFIG_DIR/plans/p.md"
  refused write_ "$CLAUDE_CONFIG_DIR/projects/$ENC/memory/m.md"
  mkdir -p "$HOME/.claude"; refused write_ "$HOME/.claude/projects/$ENC/memory/MEMORY.md"
  p="$(printf '*** Begin Patch\n*** Add File: %s/projects/%s/memory/m.md\n+x\n*** End Patch' "$CLAUDE_CONFIG_DIR" "$ENC")"
  refused call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
  export DEVWARD_DEV=1  # a development session keeps its memory
  allowed write_ "$CLAUDE_CONFIG_DIR/projects/$ENC/memory/m.md"
  unset DEVWARD_DEV
  refused write_ "/private/tmp/claude-$(id -u)/-Users-someone-other/s/notes.md"
  refused write_ "$CLAUDE_CONFIG_DIR/settings.json"
  refused write_ "$HOME/.zshrc"
}
@test "DEVWARD_DEV=1 without the marker gets the allow-list; no person's session can write the marker (A14)" {
  export DEVWARD_DEV=1
  allowed sh_ 'ls'
  rm "$HOME/.config/devward/dev"
  refused sh_ 'ls'
  refused write_ "$REPO/checks/run.sh"
  unset DEVWARD_DEV
  refused write_ "$HOME/.config/devward/dev"
  refused write_ "~/.config/devward/dev"
  p="$(printf '*** Begin Patch\n*** Add File: %s/.config/devward/dev\n+x\n*** End Patch' "$HOME")"
  refused call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
}
@test "a patch header hidden behind Unicode space, or written without a space, is still checked" {
  for sp in "$(printf '\xc2\xa0')" "$(printf '\xef\xbb\xbf')" "$(printf '\xe2\x80\x83')" ' '; do
    p="$(printf '*** Begin Patch\n*** Add File: %s/plans/x.md\n+x\n%s*** Add File: %s/.claude/hooks/guard.sh\n+exit 0\n*** End Patch' \
      "$CLAUDE_CONFIG_DIR" "$sp" "$REPO")"
    refused call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
  done
  p="$(printf '*** Begin Patch\n*** Add File:%s/checks/run.sh\n+x\n*** End Patch' "$REPO")"
  refused call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
  p="$(printf '*** Begin Patch\n*** Add File: %s/plans/x.md\n+x\n*** Delete Fil: %s/checks/run.sh\n*** End Patch' "$CLAUDE_CONFIG_DIR" "$REPO")"
  refused call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
  p="$(printf '*** Begin Patch\n*** Add File: %s/plans/x.md\n+x\n*** End Patch' "$CLAUDE_CONFIG_DIR")"
  allowed call apply_patch "$(jq -cn --arg p "$p" '{command:$p}')"
}
@test "a name or reason may hold accented letters inside quotes; folders, ids and invisible characters may not" {
  allowed sh_ 'summary/build.sh --name "José García"'
  allowed sh_ "checks/accept.sh BL-RC-01 \"I don$(printf '\xe2\x80\x99')t use VS Code\""
  run sh_ 'checks/private.sh add "~/Documents/Société"'; [ "$status" -eq 2 ]; [[ "$output" == *"Terminal app"* ]]
  refused sh_ "summary/build.sh --name \"a$(printf '\xe2\x80\xae')b\""
  refused sh_ 'summary/build.sh --name José'
  refused sh_ 'checks/run.sh --only "BL-RC-0١"'
  refused sh_ "fixes/macos/BL-RC-01.sh 'apply|undo'"
  refused sh_ "checks/overlays.sh 'new|list'"
}
@test "the Artifact tool publishes only a file the read tools may read; plan mode can be left" {
  allowed call Artifact '{"file_path":"reports/latest/posture-summary.html","icon":"shield"}'
  allowed call Artifact '{"action":"list"}'
  refused call Artifact "$(jq -cn --arg p "$HOME/.ssh/id_ed25519" '{file_path:$p}')"
  refused call Artifact '{"file_path":"private-paths"}'
  refused call Artifact '{"file_paths":["reports/x.png","/etc/hosts"],"asset":true,"url":"https://claude.ai/artifact/x"}'
  refused call Artifact '{"file_path":"reports/a.html","files":{"x.css":"/etc/hosts"}}'
  refused call Artifact '{"file_path":"reports/a.html","files":{"x.css":{"from":"../x"}}}'
  refused call Artifact '{"file_path":"a.html","files":{"x.css":"b.css"},"root":"/Users"}'
  refused call Artifact '{"action":"read","url":"https://claude.ai/artifact/x","path":"a","out_dir":"checks"}'
  allowed call ExitPlanMode '{}'
  allowed call EnterPlanMode '{}'
}
@test "reads stay in the checkout and the agent's own folders, never private-paths, approvals or .git" {
  allowed read_ controls/controls.json
  allowed read_ "$REPO/teach/BL-RC-01.md"
  allowed read_ reports/latest/results.json
  allowed read_ .claude/skills/posture/SKILL.md
  allowed read_ "$SCR/s/tasks/x.output"
  allowed read_ "$CLAUDE_CONFIG_DIR/projects/$ENC/x/tool-results/a.txt"
  refused read_ "/private/tmp/claude-$(id -u)/-Users-someone-other/s/tasks/x.output"
  refused call Grep "$(jq -cn --arg p "/private/tmp/claude-$(id -u)" '{pattern:"BEGIN", path:$p}')"
  refused read_ "$CLAUDE_CONFIG_DIR/plans/other-project.md"
  for p in private-paths PRIVATE-PATHS ./private-paths reports/.approvals/BL-RC-01.apply reports/.APPROVALS \
    .git/config .git "$REPO/.git/HEAD" ../outside.txt "$HOME/.ssh/id_ed25519" /etc/hosts "~/.zshrc" controls/../private-paths \
    "$CLAUDE_CONFIG_DIR/settings.json" "$CLAUDE_CONFIG_DIR/projects/other/memory/m.md"; do
    refused read_ "$p"
  done
  ln -s "$HOME" "$BATS_TEST_TMPDIR/h"; refused read_ "$BATS_TEST_TMPDIR/h/x"
}
@test "a search may not reach private-paths, approvals or .git: the checkout and reports/ are not search roots" {
  allowed call Grep '{"pattern":"x","path":"controls"}'
  allowed call Grep '{"pattern":"x","path":"teach/BL-RC-01.md"}'
  allowed call Glob '{"pattern":"*.md","path":"teach"}'
  allowed call Glob '{"pattern":"teach/*.md"}' "$REPO"
  refused call Grep '{"pattern":"x"}'
  refused call Grep '{"pattern":"x","path":"."}'
  refused call Grep '{"pattern":"x","path":"reports"}'
  refused call Glob '{"pattern":"**/*"}'
  refused call Glob '{"pattern":"../**","path":"teach"}'
  refused call Glob '{"pattern":"{..,x}/*","path":"teach"}'
  refused call Glob '{"pattern":"/Users/*"}'
  refused call Grep '{"pattern":"x","path":"teach"}' "$HOME"
}
@test "the shell runs one devward script per command: no other program, operator, expansion or quoting trick" {
  for c in 'ls' 'cat controls/controls.json' 'git status' 'jq -r .teach reports/config.json' 'id -F' \
    'checks/run.sh; ls' 'checks/run.sh && ls' 'checks/run.sh | cat' 'checks/run.sh > reports/x' 'checks/run.sh 2>&1' \
    'checks/run.sh < /dev/null' 'checks/run.sh --only $ID' 'checks/run.sh --only "$(id -F)"' 'checks/run.sh `x`' \
    "$(printf 'checks/run.sh\nls')" 'checks/run.sh \' 'checks/run.sh --only BL-RC-0\1' 'checks/run.sh &' \
    'X=1 checks/run.sh' 'env checks/run.sh' 'exec checks/run.sh' 'checks/run.sh --only BL-*' '(checks/run.sh)' \
    'checks/run.sh --only BL-RC-01 #' "checks/run.sh --only 'BL-RC-01" 'checks/private.sh add ~/x' \
    'checks/run.sh --timeout 1' 'checks/run.sh --only ../x' 'checks/diff.sh a b' 'summary/build.sh --name x /tmp/r.json' \
    'checks/show.sh private-paths' 'checks/show.sh .git/config' 'checks/show.sh reports/.approvals/BL-RC-01.apply' \
    'checks/show.sh ../x' 'checks/show.sh /etc/hosts' 'checks/configure.sh --overlays "a;b" --teach yes' \
    'checks/accept.sh BL-RC-01' 'checks/update.sh' 'make test' 'bats tests/hooks.bats'; do
    refused sh_ "$c"
  done
  run sh_ 'sudo spctl --global-enable'; [ "$status" -eq 2 ]; [[ "$output" == *"never runs sudo"* ]]
  run sh_ 'checks/baseline.sh accept'; [[ "$output" == *"Terminal app"* ]]
  run sh_ 'checks/private.sh remove "~/x"'; [[ "$output" == *"Terminal app"* ]]
  run sh_ 'cat reports/latest/results.json'; [[ "$output" == *"checks/show.sh"* ]]
}
@test "every command the skills give the agent is allowed, and the ones they give the person are refused" {
  n=0; seen=""
  while IFS= read -r c; do
    case "$c" in
      'checks/private.sh remove'*|'checks/baseline.sh accept'*|'checks/update.sh'*) refused sh_ "$c" ;;
      *) allowed sh_ "$c" ;;
    esac
    n=$((n + 1)); seen="$seen|$c|"
  done <<EOF
$(perl -ne 'while (/`([^`]+)`/g) { my $c = $1; print "$c\n" if $c =~ m{^(?:checks|summary|fixes)/\S+\.sh(?:\s|$)} || $c =~ /^(?:jq|id|cat|git|ls|grep|sed|awk|head|bash|sh|perl|python3|curl|codex|claude|opencode|sudo|make)\s/ }' \
  "$REPO"/.agents/skills/*/SKILL.md \
  | sed -e 's/<ID>/BL-RC-01/g' -e 's#"<path>"#"~/Documents/Private"#g' -e 's/"<[^>]*>"/"tls-proxy"/g' \
        -e 's/<path>/reports\/latest\/results.json/g' -e 's/yes|no/yes/g' -e 's/apply|undo|accept/apply/g' -e 's/apply|undo/apply/g')
EOF
  [ "$n" -ge 10 ]
  # A15, A21: the posture skill asks the canonical question, naming the folder, before it adds that folder
  [[ "$seen" == *'|checks/ask.sh private add "~/Documents/Private"|'* ]]; [[ "$seen" == *'|checks/private.sh add "~/Documents/Private"|'* ]]
  refused sh_ 'checks/ask.sh private remove'
  refused sh_ 'checks/ask.sh private add'
  refused sh_ 'checks/ask.sh private add Documents'
}
@test "checks/scan.sh runs with one quoted folder, in its one spelling, and nothing else" {
  allowed sh_ 'checks/scan.sh "~/Downloads/take-home test"'
  allowed sh_ "checks/scan.sh $HOME/dev/app"
  for c in 'checks/scan.sh' 'checks/scan.sh ~/dev/app' 'checks/scan.sh dev/app' 'checks/scan.sh .' \
    'checks/scan.sh "~/dev/a" "~/dev/b"' 'checks/scan.sh --json "~/dev/app"' './checks/scan.sh "~/dev/app"' \
    'bash checks/scan.sh "~/dev/app"' "$REPO/checks/scan.sh \"~/dev/app\"" 'checks/scan.sh "~/dev/app" | cat' \
    'checks/scan.sh "~/Documents/Société"' 'checks/scan.sh "$HOME/dev"' 'checks/scan.sh "~/dev/app"; ls'; do
    refused sh_ "$c"
  done
  refused sh_ 'checks/scan.sh "~/dev/app"' "$BATS_TEST_TMPDIR"
}
@test "checks/show.sh reads files under a dot folder in the repo, but never .git, the approval tokens or private-paths" {
  allowed sh_ 'checks/show.sh .agents/skills/fix/SKILL.md'
  allowed sh_ 'checks/show.sh .github/allowed_signers'
  for f in .git/config .GIT/config ./private-paths ./reports/.approvals/BL-RC-01.apply .. ./../x .claude/../../x; do
    refused sh_ "checks/show.sh $f"
  done
  run "$REPO/checks/show.sh" .github/allowed_signers; [ "$status" -eq 0 ]; [ "$output" = "$(cat "$REPO/.github/allowed_signers")" ]
}
@test "Codex sends its shell command as an argv list; the script inside bash -lc is what's checked" {
  allowed call Bash '{"command":["bash","-lc","checks/run.sh --only BL-RC-01"]}'
  allowed call Bash '{"command":["checks/run.sh","--only","BL-RC-01"]}'
  refused call Bash '{"command":["bash","-lc","ls"]}'
  refused call Bash '{"command":["bash","reports/s.sh"]}'
  refused call Bash '{"command":["checks/run.sh","--only","$(x)"]}'
}
@test "the guard fails closed on unreadable input" {
  run bash -c "printf 'not json' | '$G'"; [ "$status" -eq 2 ]
  run bash -c "printf '' | '$G'"; [ "$status" -eq 2 ]
  refused call Bash '{}'
}
