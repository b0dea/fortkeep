# shellcheck shell=bash disable=SC2034 # read by run.sh, which sources this file
about="/posture with set-up done and no results yet"
prompt="${S}posture"
setup() { configured; results "BL-RC-01=FAIL=folderOpen tasks allowed in VS Code"; }
expect() {
  check "agent: ran checks/run.sh" shell 'checks/run.sh'
  check "agent: reported the FAIL" said 'BL-RC-01|automatic tasks|VS Code'
}
