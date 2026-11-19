load helpers

setup() { setup_env; }
chk() { run /bin/bash "$REPO/checks/macos/$1.sh"; }

@test "BL-OS-01 FileVault on → PASS" {
  stub fdesetup 'echo true'
  chk BL-OS-01; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "FileVault: On" ]
}
@test "BL-OS-01 FileVault off → FAIL" {
  stub fdesetup 'echo false; exit 1'
  chk BL-OS-01; [ "$(field status)" = FAIL ]
}
@test "BL-OS-01 odd output → ERROR" {
  stub fdesetup 'echo "something else"'
  chk BL-OS-01; [ "$(field status)" = ERROR ]
}

fw() {
  export DEVWARD_SOCKETFILTERFW="$BATS_TEST_TMPDIR/bin/socketfilterfw"
  stub socketfilterfw "case \"\$1\" in --getglobalstate) echo '$1';; --getstealthmode) echo '$2';; esac"
}
@test "BL-OS-02 firewall + stealth on → PASS" {
  fw 'Firewall is enabled. (State = 1)' 'Firewall stealth mode is on'
  chk BL-OS-02; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "Firewall: on; stealth: on" ]
}
@test "BL-OS-02 block-all state counts as on" {
  fw 'Firewall is enabled. (State = 2)' 'Firewall stealth mode is on'
  chk BL-OS-02; [ "$(field status)" = PASS ]
}
@test "BL-OS-02 stealth off → FAIL" {
  fw 'Firewall is enabled. (State = 1)' 'Firewall stealth mode is off'
  chk BL-OS-02; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Firewall: on; stealth: off" ]
}
@test "BL-OS-02 firewall off → FAIL" {
  fw 'Firewall is disabled. (State = 0)' 'Firewall stealth mode is off'
  chk BL-OS-02; [ "$(field status)" = FAIL ]
}
@test "BL-OS-02 a definite FAIL outranks an unexpected answer, and the note names it" {
  fw 'something new' 'Firewall stealth mode is off'
  chk BL-OS-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"stealth: off"* ]]; [[ "$(field note)" == *"unexpected answer"* ]]
  fw 'Firewall is disabled. (State = 0)' 'something new'
  chk BL-OS-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"Firewall: off"* ]]; [[ "$(field note)" == *"unexpected answer"* ]]
  fw 'Firewall is enabled. (State = 1)' 'something new'
  chk BL-OS-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-OS-02 tool missing → ERROR" {
  export DEVWARD_SOCKETFILTERFW=/nonexistent
  chk BL-OS-02; [ "$(field status)" = ERROR ]
}

@test "BL-OS-03 Gatekeeper on → PASS" {
  stub spctl 'echo "assessments enabled"'
  chk BL-OS-03; [ "$(field status)" = PASS ]
}
@test "BL-OS-03 Gatekeeper off → FAIL" {
  stub spctl 'echo "assessments disabled"'
  chk BL-OS-03; [ "$(field status)" = FAIL ]
}

@test "BL-OS-04 SIP on → PASS" {
  stub csrutil 'echo "System Integrity Protection status: enabled."'
  chk BL-OS-04; [ "$(field status)" = PASS ]
}
@test "BL-OS-04 SIP off → FAIL" {
  stub csrutil 'echo "System Integrity Protection status: disabled."'
  chk BL-OS-04; [ "$(field status)" = FAIL ]
}
@test "BL-OS-04 custom configuration → FAIL" {
  stub csrutil 'printf "System Integrity Protection status: unknown (Custom Configuration).\n"'
  chk BL-OS-04; [ "$(field status)" = FAIL ]
}

@test "BL-OS-02 empty firewall output → ERROR" {
  fw '' ''
  chk BL-OS-02; [ "$(field status)" = ERROR ]
}
@test "BL-OS-02 unrecognised stealth answer → ERROR" {
  fw 'Firewall is enabled. (State = 1)' 'Stealth unknown'
  chk BL-OS-02; [ "$(field status)" = ERROR ]
}
@test "BL-OS-04 unknown status without Custom Configuration → ERROR" {
  stub csrutil 'echo "System Integrity Protection status: unknown."'
  chk BL-OS-04; [ "$(field status)" = ERROR ]
}
