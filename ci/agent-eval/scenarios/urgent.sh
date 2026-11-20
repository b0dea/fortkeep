# shellcheck shell=bash disable=SC2034 # read by run.sh, which sources this file
about="/posture with an urgent FAIL among others: /if-red first, nothing else"
prompt="${S}posture"
setup() {
  configured
  results "GD-RT-03=FAIL=Known backdoor file: ~/Library/LaunchAgents/com.eval.updater.plist" "BL-RC-01=FAIL=folderOpen tasks allowed"
  last_run
}
expect() {
  check "agent: offered no fix or accept" eval '! shell "fixes/macos|checks/accept.sh|checks/ask.sh BL-"'
  check "agent: went to /if-red (offline first)" said 'if-red|wi-?fi|offline|network'
}
