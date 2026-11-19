load helpers

setup() { setup_env; unset CLOUDSDK_CONFIG GH_CONFIG_DIR; mkdir -p "$HOME/.ssh"; SD="/tmp/devward-$$"; mkdir -p "$SD"; }
teardown() { rm -rf "/tmp/devward-$$"; }
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
key() { ssh-keygen -q -t ed25519 -N "${2:-}" -C t -f "$HOME/.ssh/$1"; }
pk() { printf -- '-----BEGIN RSA %s-----\nMIIE\n-----END RSA %s-----\n' "PRIVATE KEY" "PRIVATE KEY" > "$1"; }  # FILE — a PEM private key
sock() { /usr/bin/python3 -c 'import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$1"; }

@test "BL-SE-01 no 1Password → FAIL; agent off → FAIL" {
  chk BL-SE-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed"* ]]
  mkdir -p "$DEVWARD_SYSROOT/Applications/1Password.app"
  DEVWARD_OP_SOCK="$BATS_TEST_TMPDIR/no.sock" chk BL-SE-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *off* ]]
}
@test "BL-SE-01 agent on and ssh config points at it → PASS; on but unused → FAIL" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/1Password.app"; S="$SD/a.sock"; sock "$S"
  DEVWARD_OP_SOCK="$S" chk BL-SE-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"doesn't use it"* ]]
  printf 'Host *\n  IdentityAgent "%s"\n' "$S" > "$HOME/.ssh/config"
  DEVWARD_OP_SOCK="$S" chk BL-SE-01; [ "$(field status)" = PASS ]
}
@test "BL-SE-01 Secretive's agent, set as IdentityAgent → PASS naming it; installed but not running → FAIL" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/Secretive.app"; S="$SD/s.sock"
  DEVWARD_SECRETIVE_SOCK="$S" chk BL-SE-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"Secretive SSH agent is off"* ]]
  sock "$S"; printf 'Host *\n  IdentityAgent "%s"\n' "$S" > "$HOME/.ssh/config"
  DEVWARD_SECRETIVE_SOCK="$S" chk BL-SE-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *Secretive* ]]
}
@test "BL-SE-01 Bitwarden's agent through SSH_AUTH_SOCK → PASS naming it; a socket of an app that isn't installed doesn't count" {
  S="$SD/b.sock"; sock "$S"; printf 'export SSH_AUTH_SOCK="%s"\n' "$S" > "$HOME/.zshenv"
  DEVWARD_BW_SOCK="$S" chk BL-SE-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed"* ]]
  mkdir -p "$DEVWARD_SYSROOT/Applications/Bitwarden.app"
  DEVWARD_BW_SOCK="$S" chk BL-SE-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *Bitwarden* ]]
}
@test "BL-SE-02 no key files → PASS; a key without a passphrase → FAIL naming it; with one → PASS" {
  chk BL-SE-02; [ "$(field status)" = PASS ]
  key id_ed25519 ""
  chk BL-SE-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *id_ed25519* ]]
  rm "$HOME/.ssh/id_ed25519"*; key work_key "s3cret-phrase"
  chk BL-SE-02; [ "$(field status)" = PASS ]; [[ "$output" != *s3cret* ]]
}
@test "BL-SE-02 and BL-SE-07 never read a private ~/.ssh: ERROR saying only that a private folder was excluded" {
  key id_ed25519 ""; echo '~/.ssh' > "$DEVWARD_PRIVATE_PATHS"
  stub ssh-keygen 'echo opened >> "$BATS_TEST_TMPDIR/opened"; exit 1'
  for c in BL-SE-02 BL-SE-07; do
    chk "$c"; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]; [[ "$output" != *id_ed25519* ]]
  done
  [ ! -e "$BATS_TEST_TMPDIR/opened" ]
}
@test "BL-SE-02 a security-key (-sk) file without a passphrase passes: it works only with its hardware key" {
  printf -- '-----BEGIN OPENSSH %s-----\nb3Bl\n-----END OPENSSH %s-----\n' "PRIVATE KEY" "PRIVATE KEY" > "$HOME/.ssh/id_ed25519_sk"
  stub ssh-keygen 'echo "sk-ssh-ed25519@openssh.com AAAAGnNr t"'
  chk BL-SE-02; [ "$(field status)" = PASS ]
  stub ssh-keygen 'echo "ssh-ed25519 AAAAC3Nz t"'
  chk BL-SE-02; [ "$(field status)" = FAIL ]
}
@test "BL-SE-02 an unreadable key file → ERROR with evidence" {
  key locked "pw"; chmod 000 "$HOME/.ssh/locked"
  chk BL-SE-02; chmod 600 "$HOME/.ssh/locked"
  if [ "$(id -u)" -ne 0 ]; then [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *locked* ]]; fi
}
@test "BL-SE-03 key and secret files in Downloads, Desktop or home → FAIL; deep project .env → not counted" {
  mkdir -p "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents/p/app" "$HOME/Documents/p/node_modules/x"
  chk BL-SE-03; [ "$(field status)" = PASS ]
  touch "$HOME/Documents/p/app/.env" "$HOME/Documents/p/node_modules/x/key.pem"
  chk BL-SE-03; [ "$(field status)" = PASS ]
  pk "$HOME/Downloads/server.pem"; touch "$HOME/.env" "$HOME/Desktop/sa-key-prod.json"
  chk BL-SE-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "3 "* ]]
  [[ "$(field note)" == *"Downloads/server.pem"* ]]
}
@test "BL-SE-03 a folder whose read waits on macOS's privacy prompt → ERROR asking to answer it, not a timeout" {
  mkdir -p "$HOME/Downloads" "$HOME/Documents"
  stub ls 'case "$1" in */Documents) sleep 30 ;; esac; exec /bin/ls "$@"'
  start=$(date +%s); chk BL-SE-03
  [ $(( $(date +%s) - start )) -lt 15 ]
  [ "$(field status)" = ERROR ]; [ "$(field evidence)" = "Could not read 1 folder(s)" ]
  [ "$(field note)" = "macOS is asking whether this app may read: ~/Documents; answer that prompt, then run the check again" ]
  pk "$HOME/Downloads/server.pem"
  chk BL-SE-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"server.pem. macOS is asking whether this app may read: ~/Documents"* ]]
}
@test "BL-SE-03 a .key or .pem counts only with a private key in it: Keynote documents and test fixtures don't" {
  mkdir -p "$HOME/Documents/talks" "$HOME/Downloads"
  printf 'PK\003\004 keynote zip' > "$HOME/Documents/talks/Roadmap.key"; touch "$HOME/Downloads/empty.pem"
  printf 'not a key\n' > "$HOME/Downloads/fixture.KEY"
  chk BL-SE-03; [ "$(field status)" = PASS ]
  pk "$HOME/Downloads/tls.key"; printf -- '-----BEGIN OPENSSH %s-----\nb3Bl\n' "PRIVATE KEY" > "$HOME/Documents/deploy.PEM"
  chk BL-SE-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "2 "* ]]
  [[ "$(field note)" == *tls.key* ]]; [[ "$(field note)" == *deploy.PEM* ]]; [[ "$(field note)" != *Roadmap* ]]
}
@test "BL-SE-03 a .pem holding only certificates is public, not counted; one with a private key is" {
  mkdir -p "$HOME/Downloads"
  printf -- '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n' > "$HOME/.proxy-ca.pem"
  cat "$HOME/.proxy-ca.pem" "$HOME/.proxy-ca.pem" > "$HOME/Downloads/bundle.pem"
  chk BL-SE-03; [ "$(field status)" = PASS ]
  { cat "$HOME/.proxy-ca.pem"; printf -- '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n'; } > "$HOME/Downloads/both.pem"
  chk BL-SE-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "1 "* ]]
  [[ "$(field note)" == *both.pem* ]]; [[ "$output" != *MIIE* ]]
}
@test "BL-SE-03 never looks inside a private folder" {
  mkdir -p "$HOME/Documents/Secret"; touch "$HOME/Documents/Secret/x.pem"
  printf '~/Documents/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  chk BL-SE-03; [ "$(field status)" = PASS ]; [[ "$output" != *Secret* ]]
}
@test "BL-SE-03 an unreadable folder → ERROR with evidence" {
  mkdir -p "$HOME/Downloads"; chmod 000 "$HOME/Downloads"
  chk BL-SE-03; chmod 755 "$HOME/Downloads"
  if [ "$(id -u)" -ne 0 ]; then [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *Downloads* ]]; fi
}
@test "BL-SE-07 keys older than a year → FAIL; recent → PASS" {
  key fresh "pw"
  chk BL-SE-07; [ "$(field status)" = PASS ]
  key old "pw"; touch -t 202001010000 "$HOME/.ssh/old"
  chk BL-SE-07; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *old* ]]
}
@test "BL-SE-03 a private search folder is never listed or named, readable or not" {
  mkdir -p "$HOME/Downloads"; touch "$HOME/Downloads/x.pem"
  printf '~/Downloads\n' > "$DEVWARD_PRIVATE_PATHS"
  chk BL-SE-03; [ "$(field status)" = PASS ]; [[ "$output" != *Downloads* ]]; [[ "$(field note)" == *"private folder was excluded"* ]]
  chmod 000 "$HOME/Downloads"
  chk BL-SE-03; chmod 755 "$HOME/Downloads"
  [ "$(field status)" != ERROR ]; [[ "$output" != *Downloads* ]]; [[ "$(field note)" == *"private folder was excluded"* ]]
}
@test "BL-SE-07 an unreadable key file → ERROR with evidence; an old key still FAILs and names it" {
  key locked "pw"; chmod 000 "$HOME/.ssh/locked"
  chk BL-SE-07
  if [ "$(id -u)" -ne 0 ]; then
    [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *locked* ]]
    key old "pw"; touch -t 202001010000 "$HOME/.ssh/old"
    chk BL-SE-07; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *old* ]]; [[ "$(field note)" == *locked* ]]
  fi
  chmod 600 "$HOME/.ssh/locked"
}
@test "BL-SE-01 a hanging Match exec in the ssh config → ERROR with evidence, not a hang" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/1Password.app"; S="$SD/a.sock"; sock "$S"
  printf 'Match exec "sleep 20"\n  User x\n' > "$HOME/.ssh/config"
  DEVWARD_SHELL_TIMEOUT=1 DEVWARD_OP_SOCK="$S" chk BL-SE-01
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-01 a zsh that hangs while reading SSH_AUTH_SOCK → ERROR with evidence, not FAIL" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/1Password.app"; S="$SD/a.sock"; sock "$S"
  echo 'sleep 20' > "$HOME/.zshenv"
  DEVWARD_SHELL_TIMEOUT=1 DEVWARD_OP_SOCK="$S" chk BL-SE-01
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-01 ssh that can't read its config → ERROR unless SSH_AUTH_SOCK decides" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/1Password.app"; S="$SD/a.sock"; sock "$S"
  printf 'Bogus yes\n' > "$HOME/.ssh/config"
  DEVWARD_OP_SOCK="$S" chk BL-SE-01
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  printf 'export SSH_AUTH_SOCK="%s"\n' "$S" > "$HOME/.zshenv"
  DEVWARD_OP_SOCK="$S" chk BL-SE-01; [ "$(field status)" = PASS ]
}
@test "BL-SE-04 no gh → NA; not logged in → NA; fine-grained → PASS; classic → FAIL; nothing printed" {
  chk BL-SE-04; [ "$(field status)" = NA ]
  stub gh '[ "$1 $2" = "auth token" ] && [ -n "${TOK:-}" ] && echo "$TOK"; [ -n "${TOK:-}" ]'
  chk BL-SE-04; [ "$(field status)" = NA ]
  TOK=github_pat_11AAAAsecretpart chk BL-SE-04; [ "$(field status)" = PASS ]; [[ "$output" != *secretpart* ]]
  TOK=gho_secretpart chk BL-SE-04; [ "$(field status)" = FAIL ]; [[ "$output" != *secretpart* ]]
}
@test "BL-SE-04 a token stored in a plain file → FAIL" {
  stub gh 'echo github_pat_x'
  mkdir -p "$HOME/.config/gh"; printf 'github.com:\n    oauth_token: github_pat_x\n' > "$HOME/.config/gh/hosts.yml"
  chk BL-SE-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"plain file"* ]]
}
@test "BL-SE-04 an unrecognised token kind → ERROR with evidence and note" {
  stub gh 'echo weirdprefix_secretpart'
  chk BL-SE-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [ -n "$(field note)" ]; [[ "$output" != *secretpart* ]]
}
@test "BL-SE-05 counts long-lived AWS keys and service-account files, never values" {
  chk BL-SE-05; [ "$(field status)" = NA ]
  mkdir -p "$HOME/.aws"; printf '[a]\naws_access_key_id = ASIAEXAMPLEONLY\n' > "$HOME/.aws/credentials"
  chk BL-SE-05; [ "$(field status)" = PASS ]
  printf '[b]\naws_access_key_id = AKIAEXAMPLEONLY\naws_secret_access_key = shh\n' >> "$HOME/.aws/credentials"
  chk BL-SE-05; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"1 long-lived AWS"* ]]; [[ "$output" != *AKIAEXAMPLE* ]]
  rm "$HOME/.aws/credentials"; mkdir -p "$HOME/.config/gcloud"
  echo '{"type":"service_account","private_key":"x"}' > "$HOME/.config/gcloud/application_default_credentials.json"
  chk BL-SE-05; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *service-account* ]]
}
@test "BL-SE-06 gitleaks as a global pre-commit hook → PASS; missing → FAIL" {
  REAL_GIT="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v git)"
  stub git "[ \"\$1\" = --version ] && { echo 'git version 2.56.0'; exit 0; }; exec '$REAL_GIT' \"\$@\""
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
  chk BL-SE-06; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed"* ]]
  stub gitleaks 'exit 0'
  chk BL-SE-06; [ "$(field status)" = FAIL ]
  git config --global hook.gl.event pre-commit; git config --global hook.gl.command "$BATS_TEST_TMPDIR/bin/gitleaks git --pre-commit --staged"
  chk BL-SE-06; [ "$(field status)" = PASS ]
}
@test "BL-SE-06 a login shell that hangs → ERROR with evidence, not 'not installed'" {
  stub gitleaks 'exit 0'
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\nsleep 20\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zprofile"
  DEVWARD_SHELL_TIMEOUT=1 chk BL-SE-06
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-06 a global git config git can't read → ERROR with evidence, not FAIL" {
  stub gitleaks 'exit 0'
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
  printf '[hook\n' > "$HOME/.gitconfig"
  chk BL-SE-06
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-08 no Time Machine → NA; transcripts included → FAIL; excluded → PASS" {
  C="$BATS_TEST_TMPDIR/c1"; mkdir -p "$C/projects"; export DEVWARD_CLAUDE_DIRS="$C"
  stub tmutil 'case "$1" in destinationinfo) [ -n "${TM:-}" ] && echo "Name : Backups" || echo "tmutil: No destinations configured." ;; isexcluded) [ -n "${EXCL:-}" ] && echo "[Excluded]    $2" || echo "[Included]    $2" ;; esac'
  chk BL-SE-08; [ "$(field status)" = NA ]
  TM=1 chk BL-SE-08; [ "$(field status)" = FAIL ]
  TM=1 EXCL=1 chk BL-SE-08; [ "$(field status)" = PASS ]
}
@test "BL-SE-05 an unreadable credentials file → ERROR with evidence, not PASS" {
  mkdir -p "$HOME/.aws"; printf '[b]\naws_access_key_id = AKIAEXAMPLEONLY\n' > "$HOME/.aws/credentials"; chmod 000 "$HOME/.aws/credentials"
  chk BL-SE-05; chmod 600 "$HOME/.aws/credentials"
  if [ "$(id -u)" -ne 0 ]; then [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$output" != *AKIAEXAMPLE* ]]; [[ "$output" != *"$HOME"* ]]; fi
}
@test "BL-SE-04 a gh that hangs → ERROR, not NA" {
  stub gh 'sleep 5'
  DEVWARD_GH_TIMEOUT=1 chk BL-SE-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-04 gh exiting 0 with no output → ERROR" {
  stub gh 'exit 0'
  chk BL-SE-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SE-08 a failing isexcluded → ERROR naming the folder; an included folder still FAILs" {
  C="$BATS_TEST_TMPDIR/c1"; mkdir -p "$C/projects"; export DEVWARD_CLAUDE_DIRS="$C"
  stub tmutil 'case "$1" in destinationinfo) echo "Name : Backups" ;; isexcluded) exit 1 ;; esac'
  chk BL-SE-08; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *projects* ]]
  stub tmutil 'case "$1" in destinationinfo) echo "Name : Backups" ;; isexcluded) case "$2" in */projects) echo "[Included]    $2" ;; *) exit 1 ;; esac ;; esac'
  mkdir -p "$HOME/.codex/sessions"
  chk BL-SE-08; [ "$(field status)" = FAIL ]
}
@test "BL-SE-08 no transcript folder left because a private one was excluded → ERROR, not NA" {
  C="$BATS_TEST_TMPDIR/c1"; mkdir -p "$C/projects"; export DEVWARD_CLAUDE_DIRS="$C"; printf '%s\n' "$C" > "$DEVWARD_PRIVATE_PATHS"
  stub tmutil 'case "$1" in destinationinfo) echo "Name : Backups" ;; isexcluded) echo "[Excluded]    $2" ;; esac'
  chk BL-SE-08; [ "$(field status)" = ERROR ]; [ "$(field note)" = "a private folder was excluded" ]; [[ "$output" != *c1* ]]
}
@test "BL-SE-02 a FAIL also names the key files it couldn't read" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  key id_ed25519 ""; key locked "pw"; chmod 000 "$HOME/.ssh/locked"
  chk BL-SE-02; chmod 600 "$HOME/.ssh/locked"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not read: locked"* ]]
}
@test "BL-SE-03 a FAIL also names the folders it couldn't read, and still says a private folder was excluded" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  mkdir -p "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; pk "$HOME/Downloads/server.pem"; chmod 000 "$HOME/Documents"
  echo '~/Desktop' > "$DEVWARD_PRIVATE_PATHS"
  chk BL-SE-03; chmod 755 "$HOME/Documents"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"blocked reading: ~/Documents"* ]]; [[ "$(field note)" == *"private folder was excluded"* ]]
}
@test "teach/BL-SE-03 'Check it yourself' uses stock find, not fd" {
  # The section runs from its label to the next one: the command sits in an indented block below the label.
  section="$(awk '/^\*\*Check it yourself:\*\*/ { on = 1 } /^\*\*How to fix:\*\*/ { on = 0 } on' "$REPO/teach/BL-SE-03.md")"
  [[ "$section" == *'    find ~/Downloads ~/Desktop ~/Documents -maxdepth 4 -type f'* ]]
  [[ "$section" != *'fd '* ]]
}
