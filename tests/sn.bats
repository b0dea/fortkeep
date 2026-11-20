load helpers

setup() {
  setup_env
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
}
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
homebrew() {  # a fake Homebrew whose vulns command exists
  H="$BATS_TEST_TMPDIR/hb"; mkdir -p "$H/bin" "$H/Library/Homebrew/cmd"
  printf '#!/bin/sh\n' > "$H/bin/brew"; chmod +x "$H/bin/brew"; touch "$H/Library/Homebrew/cmd/vulns.rb"
  ln -s "$H/bin/brew" "$BATS_TEST_TMPDIR/bin/brew"
}

@test "BL-SN-01 names the missing scanners" {
  for t in osv-scanner pip-audit gitleaks; do stub "$t" 'exit 0'; done
  chk BL-SN-01; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *cosign* ]]; [[ "$(field note)" == *shellcheck* ]]; [[ "$(field note)" == *actionlint* ]]
  [[ "$(field note)" != *osv-scanner* ]]
}
@test "BL-SN-01 all scanners and brew vulns → PASS; Homebrew without vulns → FAIL" {
  for t in osv-scanner pip-audit gitleaks cosign shellcheck actionlint; do stub "$t" 'exit 0'; done
  chk BL-SN-01; [ "$(field status)" = PASS ]
  homebrew; chk BL-SN-01; [ "$(field status)" = PASS ]
  rm "$BATS_TEST_TMPDIR/hb/Library/Homebrew/cmd/vulns.rb"
  chk BL-SN-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"brew vulns"* ]]
}
@test "BL-SN-01 a login shell that hangs → ERROR with evidence" {
  printf 'sleep 30\n' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SN-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SN-01 a brew whose location cannot be resolved → ERROR with evidence" {
  for t in osv-scanner pip-audit gitleaks cosign shellcheck actionlint; do stub "$t" 'exit 0'; done
  stub brew 'exit 0'; stub perl 'exit 1'
  chk BL-SN-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SN-02 nuclei → PASS; none → FAIL" {
  chk BL-SN-02; [ "$(field status)" = FAIL ]
  stub nuclei 'exit 0'; chk BL-SN-02; [ "$(field status)" = PASS ]
}
@test "BL-SN-02 a login shell that hangs → ERROR with evidence" {
  printf 'sleep 30\n' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SN-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-IS-01 an app or a CLI counts; none → FAIL" {
  chk BL-IS-01; [ "$(field status)" = FAIL ]
  mkdir -p "$FORTKEEP_SYSROOT/Applications/OrbStack.app"; chk BL-IS-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *OrbStack* ]]
  rm -r "$FORTKEEP_SYSROOT/Applications/OrbStack.app"; stub colima 'exit 0'
  chk BL-IS-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *colima* ]]
}
@test "BL-IS-01 a login shell that hangs and no app → ERROR; an app still counts" {
  printf 'sleep 30\n' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-IS-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
  mkdir -p "$FORTKEEP_SYSROOT/Applications/UTM.app"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-IS-01; [ "$(field status)" = PASS ]
}
