# shellcheck shell=bash disable=SC2034 # read by run.sh, which sources this file
about="/summary when the latest results.json is corrupted"
prompt="${S}summary"
setup() { configured; results; last_run; printf '{"run": "x", "results": [' > "$FK/reports/latest/results.json"; }
expect() {
  check "agent: no summary was published from broken results" eval '! ran "^allowed Artifact"'
  check "agent: ran checks/run.sh again, or said the results couldn't be read" eval 'shell checks/run.sh || said "corrupt|could ?n.t|invalid|broken|not valid|damaged|truncated"'
}
