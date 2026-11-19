load helpers

setup() {
  setup_env; stub pgrep 'case " $RUNNING " in *" $2 "*) exit 0 ;; *) exit 1 ;; esac'
  sysext  # never this Mac's own extensions
  stub systemextensionsctl '[ "$1" = list ] && cat "$BATS_TEST_TMPDIR/sysext"'
}
sysext() {  # LINE... — systemextensionsctl list output: one section, each LINE "bundle (version)|name|[state]"
  local l; { echo "$# extension(s)"
    printf -- '--- com.apple.system_extension.endpoint_security\nenabled\tactive\tteamID\tbundleID (version)\tname\t[state]\n'
    for l in "$@"; do printf '*\t*\tTEAMID0001\t%s\n' "$(printf '%s' "$l" | tr '|' '\t')"; done; } > "$BATS_TEST_TMPDIR/sysext"
}
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
app() { mkdir -p "$DEVWARD_SYSROOT/Applications/$1.app"; }

@test "BL-RT-01 missing → FAIL; installed but not running → FAIL; running → PASS" {
  chk BL-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not installed"* ]]
  mkdir -p "$DEVWARD_SYSROOT/Library/Objective-See/BlockBlock"; app "BlockBlock Helper"
  chk BL-RT-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"not running"* ]]
  RUNNING="BlockBlock" chk BL-RT-01; [ "$(field status)" = PASS ]
}
@test "BL-RT-02 KnockKnock missing → FAIL; installed → PASS" {
  chk BL-RT-02; [ "$(field status)" = FAIL ]
  app KnockKnock; chk BL-RT-02; [ "$(field status)" = PASS ]
}
@test "BL-RT-03 none → FAIL; LuLu running → PASS by alternative; Little Snitch installed but stopped → FAIL" {
  chk BL-RT-03; [ "$(field status)" = FAIL ]
  app LuLu; RUNNING=LuLu chk BL-RT-03; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *LuLu* ]]
  rm -r "$DEVWARD_SYSROOT/Applications/LuLu.app"; app "Little Snitch"
  chk BL-RT-03; [ "$(field status)" = FAIL ]
}
@test "BL-RT-04 OverSight or Micro Snitch → PASS; neither → FAIL" {
  chk BL-RT-04; [ "$(field status)" = FAIL ]
  app OverSight; chk BL-RT-04; [ "$(field status)" = PASS ]
}
@test "BL-RT-05 Defender's command or another product's app without a running extension → FAIL naming it; nothing → FAIL" {
  chk BL-RT-05; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "No known endpoint protection or antivirus" ]
  stub mdatp 'exit 0'; chk BL-RT-05; [ "$(field status)" = FAIL ]
  [ "$(field evidence)" = "Endpoint protection installed but not running: Microsoft Defender" ]
  rm "$BATS_TEST_TMPDIR/bin/mdatp"; app "Bitdefender Antivirus for Mac"
  sysext 'com.bitdefender.agentui.sp (1.0/1.0)|Bitdefender Security|[terminated waiting to uninstall on reboot]'
  chk BL-RT-05; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Endpoint protection installed but not running: Bitdefender Antivirus for Mac" ]
}
@test "BL-RT-05 an endpoint product's activated and enabled system extension → PASS naming each; other extensions don't count" {
  sysext 'com.crowdstrike.falcon.Agent (1.0/1.0)|Falcon Sensor|[activated enabled]' \
    'com.bitdefender.agentui.sp (1.0/1.0)|Bitdefender Security|[activated enabled]' \
    'com.crowdstrike.falcon.Agent (2.0/2.0)|Falcon Sensor|[activated enabled]' \
    'com.example.vpn.network-extension (1.0/1)|Example VPN|[activated enabled]'
  chk BL-RT-05; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "Endpoint protection running: Falcon Sensor, Bitdefender Security" ]
  sysext 'com.example.vpn.network-extension (1.0/1)|Example VPN|[activated enabled]' \
    'com.crowdstrike.falcon.Agent (1.0/1.0)|Falcon Sensor|[activated waiting for user]'
  chk BL-RT-05; [ "$(field status)" = FAIL ]
}
@test "BL-RT-05 Microsoft Defender counts by its endpoint security extension" {
  stub mdatp 'exit 0'
  sysext 'com.microsoft.wdav.epsext (1.0/1.0)|Microsoft Defender Endpoint Security Extension|[activated enabled]'
  chk BL-RT-05; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "Endpoint protection running: Microsoft Defender Endpoint Security Extension" ]
}
@test "BL-RT-05 systemextensionsctl that fails or gives no list → ERROR when a product is installed, FAIL when none is" {
  app "SentinelOne"
  stub systemextensionsctl 'exit 1'
  chk BL-RT-05; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *SentinelOne* ]]; [[ "$(field note)" == *systemextensionsctl* ]]
  stub systemextensionsctl 'echo "usage: systemextensionsctl"'
  chk BL-RT-05; [ "$(field status)" = ERROR ]
  rm -r "$DEVWARD_SYSROOT/Applications/SentinelOne.app"
  chk BL-RT-05; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "No known endpoint protection or antivirus" ]
}
@test "BL-RT-06 tirith on PATH → PASS; absent → FAIL" {
  chk BL-RT-06; [ "$(field status)" = FAIL ]
  stub tirith 'exit 0'; chk BL-RT-06; [ "$(field status)" = PASS ]
}
