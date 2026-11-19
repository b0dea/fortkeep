load helpers

setup() { setup_env; }
chk() { run /bin/bash "$REPO/checks/macos/$1.sh"; }

# defaults stub: answers from env vars named SU_<key> / CC_AIR; unset var = "does not exist"
defaults_stub() {
  stub defaults '
k="${!#}"
case "$k" in
  AirplayReceiverEnabled) v="${CC_AIR:-}" ;;
  *) eval "v=\${SU_$k:-}" ;;
esac
[ -n "$v" ] || { echo "${DEFAULTS_UNSET_MSG:-The domain/default pair does not exist}" >&2; exit 1; }
echo "$v"'
}

@test "BL-OS-05 defaults only → PASS" {
  defaults_stub; export SU_AutomaticDownload=1
  chk BL-OS-05; [ "$(field status)" = PASS ]
  [[ "$(field evidence)" == *"AutomaticCheckEnabled=default"* ]]
}
@test "BL-OS-05 security responses off → FAIL" {
  defaults_stub; export SU_CriticalUpdateInstall=0
  chk BL-OS-05; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *CriticalUpdateInstall* ]]
}

netstat_stub() {  # $1 = extra LISTEN lines; netstat -anv adds the counters and process:pid columns to each
  stub netstat "printf 'Active Internet connections (including servers)\nProto Recv-Q Send-Q  Local Address          Foreign Address        (state)          rxbytes      txbytes  rhiwat  shiwat          process:pid    state\ntcp4       0      0  127.0.0.1.53           *.*                    LISTEN\ntcp6       0      0  ::1.53                 *.*                    LISTEN\n%b' '$1' | sed 's/LISTEN *\$/LISTEN                 0            0  131072  131072        launchd:1    00100/'"
}
@test "BL-OS-06 nothing listening, AirPlay off → PASS" {
  defaults_stub; export CC_AIR=0; netstat_stub ''
  chk BL-OS-06; [ "$(field status)" = PASS ]
}
@test "BL-OS-06 Remote Login listening → FAIL" {
  defaults_stub; export CC_AIR=0
  netstat_stub 'tcp4       0      0  *.22                   *.*                    LISTEN\n'
  chk BL-OS-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Remote Login"* ]]
}
@test "BL-OS-06 loopback-only 5900 is fine" {
  defaults_stub; export CC_AIR=0
  netstat_stub 'tcp4       0      0  127.0.0.1.5900         *.*                    LISTEN\n'
  chk BL-OS-06; [ "$(field status)" = PASS ]
}
@test "BL-OS-06 AirPlay unset means on → FAIL" {
  defaults_stub; netstat_stub ''
  chk BL-OS-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"AirPlay Receiver"* ]]
}
@test "BL-OS-06 a definite FAIL outranks what couldn't be read, and the note names it" {
  defaults_stub; stub netstat 'exit 1'
  chk BL-OS-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"AirPlay Receiver"* ]]; [[ "$(field note)" == *"netstat gave no output"* ]]
  netstat_stub 'tcp4       0      0  *.22                   *.*                    LISTEN\n'
  stub defaults 'echo "Could not read domain" >&2; exit 1'
  chk BL-OS-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Remote Login"* ]]; [[ "$(field note)" == *"could not read AirPlay Receiver setting"* ]]
}
@test "BL-OS-06 a netstat table with neither a process:pid nor a pid column → ERROR, not a guess" {
  defaults_stub; export CC_AIR=0
  stub netstat "printf 'Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)\ntcp4       0      0  *.22                   *.*                    LISTEN\n'"
  chk BL-OS-06; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"listening: unknown"* ]]
}
@test "BL-OS-06 netstat prints nothing → ERROR" {
  defaults_stub; export CC_AIR=0; stub netstat 'exit 1'
  chk BL-OS-06; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"netstat gave no output"* ]]
}

@test "BL-OS-07 immediate → PASS" {
  stub sysadminctl 'echo "2026-10-16 09:51:37.659 sysadminctl[1:2] screenLock delay is immediate" >&2'
  chk BL-OS-07; [ "$(field status)" = PASS ]
}
@test "BL-OS-07 delayed → FAIL with the delay" {
  stub sysadminctl 'echo "2026-10-16 09:51:37.659 sysadminctl[1:2] screenLock delay is 300 seconds" >&2'
  chk BL-OS-07; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Screen lock: after 300 seconds" ]
}
@test "BL-OS-07 unknown wording → ERROR" {
  stub sysadminctl 'echo "something new" >&2'
  chk BL-OS-07; [ "$(field status)" = ERROR ]
}

touch_id_mac() {  # an administrator on a Mac with a Touch ID sensor, unless GROUPS_OUT, SENSOR or TEMPLATES say otherwise
  stub id 'if [ "$1" = -Gn ]; then echo "${GROUPS_OUT-staff everyone admin}"; else exec /usr/bin/id "$@"; fi'
  stub ioreg '[ -z "${SENSOR-1}" ] || echo "+-o AppleSandDollar  <class AppleSandDollar>"'
  stub bioutil 'echo "User 501:	${TEMPLATES:-0} biometric template(s)"'
}
@test "BL-OS-08 a standard (non-admin) account, or a Mac with no Touch ID sensor → NA; a paired Touch ID keyboard counts" {
  touch_id_mac
  GROUPS_OUT="staff everyone" chk BL-OS-08; [ "$(field status)" = NA ]; [[ "$(field evidence)" == *administrator* ]]
  SENSOR="" chk BL-OS-08; [ "$(field status)" = NA ]; [[ "$(field evidence)" == *"no Touch ID sensor"* ]]
  SENSOR="" TEMPLATES=2 chk BL-OS-08; [ "$(field status)" = FAIL ]
}
@test "BL-OS-08 pam_tid present → PASS" {
  mkdir -p "$DEVWARD_SYSROOT/etc/pam.d"
  printf '# comment\nauth       sufficient     pam_tid.so\n' > "$DEVWARD_SYSROOT/etc/pam.d/sudo_local"
  chk BL-OS-08; [ "$(field status)" = PASS ]
}
@test "BL-OS-08 commented out → FAIL" {
  touch_id_mac
  mkdir -p "$DEVWARD_SYSROOT/etc/pam.d"
  printf '#auth       sufficient     pam_tid.so\n' > "$DEVWARD_SYSROOT/etc/pam.d/sudo_local"
  chk BL-OS-08; [ "$(field status)" = FAIL ]
}
@test "BL-OS-08 no file → FAIL" {
  touch_id_mac
  chk BL-OS-08; [ "$(field status)" = FAIL ]
}

@test "BL-OS-09 nothing installed → PASS" {
  mkdir -p "$DEVWARD_SYSROOT/Applications" "$DEVWARD_SYSROOT/Library/LaunchDaemons"
  touch "$DEVWARD_SYSROOT/Library/LaunchDaemons/com.example.ok.plist"
  chk BL-OS-09; [ "$(field status)" = PASS ]
}
@test "BL-OS-09 leftover helper → FAIL naming it" {
  mkdir -p "$DEVWARD_SYSROOT/Library/PrivilegedHelperTools"
  touch "$DEVWARD_SYSROOT/Library/PrivilegedHelperTools/com.teamviewer.Helper"
  chk BL-OS-09; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *com.teamviewer.Helper* ]]
}
@test "BL-OS-09 app installed → FAIL" {
  mkdir -p "$DEVWARD_SYSROOT/Applications/AnyDesk.app"
  chk BL-OS-09; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *AnyDesk* ]]
}

@test "BL-OS-05 and BL-OS-06 read newer macOS's missing-key wording as not set, not as an error" {
  defaults_stub; export DEFAULTS_UNSET_MSG="Could not find key 'AutomaticCheckEnabled' in domain 'com.apple.SoftwareUpdate'."
  export SU_AutomaticDownload=1
  chk BL-OS-05; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"AutomaticCheckEnabled=default"* ]]
  chk BL-OS-06; [ "$(field status)" != ERROR ]; [[ "$(field note)" != *"could not read AirPlay"* ]]
}
@test "BL-OS-05 unreadable defaults → ERROR" {
  stub defaults 'echo "Could not read domain" >&2; exit 1'
  chk BL-OS-05; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"could not read"* ]]
}
@test "BL-OS-06 unreadable AirPlay setting → ERROR" {
  netstat_stub ''
  stub defaults 'echo "Could not read domain" >&2; exit 1'
  chk BL-OS-06; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"could not read"* ]]
}
