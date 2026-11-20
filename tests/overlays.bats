load helpers

setup() {
  setup_env; unset NODE_EXTRA_CA_CERTS SSL_CERT_FILE REQUESTS_CA_BUNDLE AWS_CA_BUNDLE
  # detect.sh asks a login shell, where path_helper puts /etc/paths.d entries (such as /opt/homebrew/bin) first:
  # without this, a varlock installed on the Mac running the tests is suggested too.
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zprofile"
}
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
pem() { printf -- '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n' > "$HOME/ca.pem"; }

@test "OV-TP-01 the three variables point at a CA bundle in every zsh → PASS" {
  pem; printf 'export NODE_EXTRA_CA_CERTS=$HOME/ca.pem SSL_CERT_FILE=$HOME/ca.pem REQUESTS_CA_BUNDLE=$HOME/ca.pem\n' > "$HOME/.zshenv"
  chk OV-TP-01; [ "$(field status)" = PASS ]
}
@test "OV-TP-01 a missing variable or file → FAIL naming it" {
  pem; printf 'export NODE_EXTRA_CA_CERTS=$HOME/ca.pem SSL_CERT_FILE=$HOME/nope.pem\n' > "$HOME/.zshenv"
  chk OV-TP-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *SSL_CERT_FILE* ]]; [[ "$(field note)" == *REQUESTS_CA_BUNDLE* ]]
  [[ "$(field note)" != *NODE_EXTRA_CA_CERTS* ]]
}
@test "OV-TP-01 a shell that hangs → ERROR with evidence" {
  pem; printf 'sleep 20\n' > "$HOME/.zshenv"
  FORTKEEP_SHELL_TIMEOUT=1 chk OV-TP-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"Timed out"* ]]
}
@test "OV-TP-01 a shell that gives no answer → ERROR with evidence" {
  pem; printf 'exit 0\n' > "$HOME/.zshenv"
  chk OV-TP-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "OV-TP-02 verify finishes → PASS; hangs → FAIL; no Safe Chain → FAIL" {
  chk OV-TP-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *BL-SC-01* ]]
  mkdir -p "$HOME/.safe-chain/shims"; printf '#!/bin/sh\nexit 0\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
  echo 'export PATH="$HOME/.safe-chain/shims:$PATH"' > "$HOME/.zshenv"
  chk OV-TP-02; [ "$(field status)" = PASS ]
  printf '#!/bin/sh\nsleep 20\n' > "$HOME/.safe-chain/shims/npm"
  FORTKEEP_VERIFY_TIMEOUT=1 chk OV-TP-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"did not finish"* ]]
}
@test "OV-TP-02 a start-up file that hangs before the verify → ERROR with evidence, not FAIL" {
  mkdir -p "$HOME/.safe-chain/shims"; printf '#!/bin/sh\nexit 0\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
  echo 'sleep 20' > "$HOME/.zshenv"
  FORTKEEP_VERIFY_TIMEOUT=1 chk OV-TP-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "OV-TP-02 verify exits non-zero → FAIL; a shell that prints nothing → ERROR with evidence" {
  mkdir -p "$HOME/.safe-chain/shims"; printf '#!/bin/sh\nexit 3\n' > "$HOME/.safe-chain/shims/npm"; chmod +x "$HOME/.safe-chain/shims/npm"
  echo 'export PATH="$HOME/.safe-chain/shims:$PATH"' > "$HOME/.zshenv"
  chk OV-TP-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"fails"* ]]
  echo 'exit 0' > "$HOME/.zshenv"
  chk OV-TP-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "OV-ME-* with nothing installed → FAIL" {
  for c in OV-ME-01 OV-ME-02 OV-ME-03; do chk "$c"; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"No endpoint protection"* ]]; done
}
@test "OV-ME-* with Defender read mdatp health only" {
  stub mdatp '[ "$1 $2" = "health --field" ] || { echo "wrong call: $*" >&2; exit 9; }
case "$3" in healthy) echo "${HL:-true}" ;; tamper_protection) echo "\"${TP:-block}\"" ;; behavior_monitoring) echo "\"${BM:-enabled}\"" ;; esac'
  chk OV-ME-01; [ "$(field status)" = PASS ]
  HL=false chk OV-ME-01; [ "$(field status)" = FAIL ]
  chk OV-ME-02; [ "$(field status)" = PASS ]
  TP=audit chk OV-ME-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *audit* ]]
  chk OV-ME-03; [ "$(field status)" = PASS ]
  BM=disabled chk OV-ME-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"security team"* ]]
}
@test "OV-ME-* with another product: installed passes; settings the agent can't read are NA, naming the product" {
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Bitdefender Antivirus for Mac.app"
  chk OV-ME-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *Bitdefender* ]]; [[ "$(field evidence)" == *"health can't be read"* ]]
  chk OV-ME-02; [ "$(field status)" = NA ]; [[ "$(field evidence)" == *Bitdefender* ]]; [[ "$(field note)" == *"security team"* ]]
  chk OV-ME-03; [ "$(field status)" = NA ]
}
@test "OV-ME-* an mdatp that hangs → ERROR with evidence" {
  stub mdatp 'sleep 30'
  for c in OV-ME-01 OV-ME-02 OV-ME-03; do
    FORTKEEP_MDATP_TIMEOUT=1 chk "$c"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  done
}
@test "OV-ME-* an mdatp that gives no answer or fails → ERROR with evidence" {
  stub mdatp 'exit 0'
  for c in OV-ME-01 OV-ME-02 OV-ME-03; do chk "$c"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; done
  stub mdatp 'echo oops; exit 4'
  for c in OV-ME-01 OV-ME-02 OV-ME-03; do chk "$c"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; done
}
@test "OV-ME-* Defender app without mdatp → ERROR with evidence" {
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Microsoft Defender.app"
  for c in OV-ME-01 OV-ME-02 OV-ME-03; do chk "$c"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; done
}
@test "fortkeep_mdatp_field never calls mdatp config" {
  stub mdatp '[ "$1" = config ] && exit 99; echo "\"x\""'
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" /bin/bash -c ". '$REPO/checks/lib/common.sh'; . '$REPO/checks/lib/apps.sh'; fortkeep_mdatp_field tamper_protection"
  [ "$status" -eq 0 ]; [ "$output" = x ]
}
@test "detect.sh suggests overlays from what it finds" {
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/detect.sh"
  [ "$(jq -c .suggest_overlays <<<"$output")" = '[]' ]
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Cloudflare WARP.app" "$FORTKEEP_SYSROOT/Applications/Bitdefender Antivirus for Mac.app"
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/detect.sh"
  [ "$(jq -c .suggest_overlays <<<"$output")" = '["tls-proxy","managed-endpoint"]' ]
  [ "$(jq -r '.endpoint[0]' <<<"$output")" = "Bitdefender Antivirus for Mac" ]
}
@test "detect.sh sees a CA bundle variable in a non-interactive zsh" {
  echo 'export SSL_CERT_FILE=/x' > "$HOME/.zshenv"
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/detect.sh"
  [ "$(jq -r .tls_interception <<<"$output")" = true ]
  [ "$(jq -c .suggest_overlays <<<"$output")" = '["tls-proxy"]' ]
}
@test "OV-ME-02/03 an unrecognised Defender value → ERROR with evidence, not FAIL" {
  stub mdatp 'case "$3" in tamper_protection) echo "ATTENTION: warning" ;; behavior_monitoring) echo "weird" ;; esac'
  chk OV-ME-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *"ATTENTION: warning"* ]]
  chk OV-ME-03; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]; [[ "$(field note)" == *weird* ]]
}
@test "OV-ME-02 a Defender tamper value of disabled → FAIL" {
  stub mdatp 'echo "\"disabled\""'
  chk OV-ME-02; [ "$(field status)" = FAIL ]
}
@test "fortkeep_mdatp_field keeps spaces inside a value and trims the outside" {
  stub mdatp 'echo "  \"a b\"  "'
  run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" /bin/bash -c ". '$REPO/checks/lib/common.sh'; . '$REPO/checks/lib/apps.sh'; fortkeep_mdatp_field x"
  [ "$output" = "a b" ]
}
@test "OV-TP-01 a FAIL also names the shells that timed out" {
  echo 'sleep 5' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk OV-TP-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Timed out: zsh -lc"* ]]
}
@test "OV-TP-01 a FAIL also names the shells that gave no answer" {
  echo 'exit 3' > "$HOME/.zlogin"
  chk OV-TP-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"No answer from: zsh -lc"* ]]
}

cfg() { run /bin/bash "$REPO/checks/configure.sh" "$@"; }
newov() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/overlays.sh" new; }
extra_overlay() {  # the real controls plus one more overlay, as if a later version of the repo added it
  jq '. + [{"id":"OV-NW-01","title":"New","layer":"overlay:new-one","level":"SHOULD","source":"x","check":"checks/fake/x.sh"}]' \
    "$REPO/controls/controls.json" > "$BATS_TEST_TMPDIR/controls.json"
  export FORTKEEP_CONTROLS="$BATS_TEST_TMPDIR/controls.json"
}
@test "overlays.sh new: a config from before offered counts its overlays as offered" {
  echo '{"overlays":["tls-proxy"],"teach":true,"configured":"2026-10-18T00:00:00Z"}' > "$FORTKEEP_CONFIG"
  newov; [ "$status" -eq 0 ]; [ "${lines[*]}" = '{"overlay":"managed-endpoint","suggested":false} {"overlay":"secrets-varlock","suggested":false}' ]
}
@test "overlays.sh new: what detect.sh suggests is marked; a full setup offers everything" {
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Bitdefender Antivirus for Mac.app"
  echo '{"overlays":[],"teach":false,"configured":"2026-10-18T00:00:00Z"}' > "$FORTKEEP_CONFIG"
  newov; [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [ "$(jq -sc 'map({(.overlay): .suggested}) | add' <<<"$output")" = '{"managed-endpoint":true,"secrets-varlock":false,"tls-proxy":false}' ]
  cfg --overlays "" --teach no; [ "$status" -eq 0 ]
  [ "$(jq -c .offered "$FORTKEEP_CONFIG")" = '["managed-endpoint","secrets-varlock","tls-proxy"]' ]
  newov; [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "a new overlay is offered once, and a no is remembered" {
  cfg --overlays "tls-proxy" --teach yes; [ "$status" -eq 0 ]
  extra_overlay
  newov; [ "$output" = '{"overlay":"new-one","suggested":false}' ]
  cfg --offered "new-one" --add-overlays ""; [ "$status" -eq 0 ]
  newov; [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(jq -c .overlays "$FORTKEEP_CONFIG")" = '["tls-proxy"]' ]
}
@test "merge mode keeps teach and the earlier choices, and records what it adds as offered" {
  cfg --overlays "tls-proxy" --teach yes; [ "$status" -eq 0 ]
  at="$(jq -r .configured "$FORTKEEP_CONFIG")"
  cfg --offered "managed-endpoint" --add-overlays "managed-endpoint"; [ "$status" -eq 0 ]
  [ "$(jq -c '{overlays, offered, teach}' "$FORTKEEP_CONFIG")" = '{"overlays":["managed-endpoint","tls-proxy"],"offered":["managed-endpoint","secrets-varlock","tls-proxy"],"teach":true}' ]
  [ "$(jq -r .configured "$FORTKEEP_CONFIG")" = "$at" ]
  echo '{"overlays":["tls-proxy"],"teach":false}' > "$FORTKEEP_CONFIG"
  cfg --offered "managed-endpoint" --add-overlays ""; [ "$status" -eq 0 ]
  [ "$(jq -c '{overlays, offered, teach}' "$FORTKEEP_CONFIG")" = '{"overlays":["tls-proxy"],"offered":["managed-endpoint","tls-proxy"],"teach":false}' ]
}
@test "configure.sh rejects unknown names in both modes, mixed modes, and a merge with no config" {
  cfg --offered "tls-proxy" --add-overlays ""; [ "$status" -eq 2 ]; [[ "$output" == *"no settings yet"* ]]
  cfg --overlays "nope" --teach yes; [ "$status" -eq 2 ]; [[ "$output" == *"unknown overlay(s): nope"* ]]
  cfg --overlays "" --teach no; [ "$status" -eq 0 ]
  cfg --offered "nope" --add-overlays ""; [ "$status" -eq 2 ]; [[ "$output" == *"unknown overlay(s): nope"* ]]
  cfg --offered "tls-proxy" --add-overlays "nope"; [ "$status" -eq 2 ]
  cfg --overlays "tls-proxy" --teach no --offered "tls-proxy"; [ "$status" -eq 2 ]; [[ "$output" == *usage* ]]
  [ "$(jq -c .overlays "$FORTKEEP_CONFIG")" = '[]' ]
}
@test "overlays.sh rejects other arguments" {
  run /bin/bash "$REPO/checks/overlays.sh"; [ "$status" -eq 2 ]
  run /bin/bash "$REPO/checks/overlays.sh" all; [ "$status" -eq 2 ]
}
