load helpers

setup() {
  T="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$T"
  cp -R "$REPO/ci" "$REPO/controls" "$T/"
  for f in $(yq -r '(select(tag == "!!seq"), (select(tag == "!!map") | .controls)) | .[] | (.check, .teach, .fix) | select(. != null)' "$T"/controls/*.yaml $(ls "$T"/controls/overlays/*.yaml 2>/dev/null)); do
    mkdir -p "$T/$(dirname "$f")"; touch "$T/$f"
  done
  N="$(jq length "$REPO/controls/controls.json")"
  "$T/ci/build-controls.sh"
}

@test "build merges all YAML into one array" {
  run jq length "$T/controls/controls.json"
  [ "$output" -eq "$N" ]
}

@test "check passes on a valid tree" {
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"controls OK ($N)"* ]]
}

@test "check fails when controls.json is stale" {
  yq -i '.[0].title = "changed"' "$T/controls/baseline.yaml"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *stale* ]]
}

@test "check reports duplicate ids, bad level and missing files" {
  yq -i '.[1].id = "BL-OS-01" | .[2].level = "MAYBE"' "$T/controls/baseline.yaml"
  rm "$T/teach/BL-OS-04.md"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: duplicate id"* ]]
  [[ "$output" == *"BL-OS-03: level"* ]]
  [[ "$output" == *"missing file: teach/BL-OS-04.md"* ]]
}

@test "mscp, when present, is a list of rule ids" {
  yq -i '.[0].mscp = ["os_sip_enable", "Not An Id"]' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]; [[ "$output" == *"BL-OS-01: mscp must be a list of mSCP rule ids"* ]]
}

@test "baseline controls need a source section" {
  yq -i 'del(.[0].source)' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: baseline control needs source"* ]]
}

@test "empty teach path is reported, not controls OK" {
  yq -i '.[0].teach = ""' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: teach path"* ]]
  [[ "$output" != *"controls OK"* ]]
}

@test "non-string id is an id-format error, not a crash" {
  yq -i '.[0].id = 5' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"5: id format"* ]]
}

@test "check rejects a timeout that is not whole seconds from 1 to 300" {
  yq -i '.[0].timeout = 0 | .[1].timeout = "x" | .[2].timeout = 30' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: timeout"* ]]; [[ "$output" == *"BL-OS-02: timeout"* ]]
  [[ "$output" != *"BL-OS-03: timeout"* ]]
}

@test "urgent is true or false; an urgent control has no fix script, and its not_urgent_if is a string" {
  yq -i '.[0].urgent = "yes" | .[1].urgent = true | .[1].fix = "checks/macos/BL-OS-02.sh" | .[2].urgent = true | .[2].not_urgent_if = 3' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: urgent must be true or false"* ]]
  [[ "$output" == *"BL-OS-02: an urgent control can't have a fix script"* ]]
  [[ "$output" == *"BL-OS-03: not_urgent_if must be a non-empty string"* ]]
}

@test "the live-malware controls are urgent and have no fix script" {
  for id in GD-RT-03 GD-AI-01 GD-RC-01; do
    jq -e --arg id "$id" '.[] | select(.id == $id) | .urgent == true and .fix == null' "$REPO/controls/controls.json"
  done
}

@test "alternatives is a list of names" {
  yq -i '.[0].alternatives = "Secretive" | .[1].alternatives = [1]' "$T/controls/baseline.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BL-OS-01: alternatives must be a list of names"* ]]; [[ "$output" == *"BL-OS-02: alternatives"* ]]
}

@test "each overlay's title and pick-this-if line are compiled onto its controls, and both are required" {
  jq -e '[.[] | select(.layer | startswith("overlay:"))] | length > 0 and all(.[];
    (.overlay.title | type == "string" and length > 0) and (.overlay.pick_if | type == "string" and length > 0))' "$T/controls/controls.json"
  [ "$(jq -r '.[] | select(.id == "OV-TP-01") | .overlay.title' "$T/controls/controls.json")" = "$(yq -r .title "$T/controls/overlays/tls-proxy.yaml")" ]
  yq -i 'del(.pick_if)' "$T/controls/overlays/tls-proxy.yaml"
  "$T/ci/build-controls.sh"
  run "$T/ci/check-controls.sh"
  [ "$status" -eq 1 ]; [[ "$output" == *"OV-TP-01: overlay needs a title and a pick_if line"* ]]
}
