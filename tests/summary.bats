load helpers

setup() {
  setup_env
  R="$DEVWARD_REPORTS/20261016T050000Z"; mkdir -p "$R"
  cat > "$R/results.json" <<EOF
{"run":"20261016T050000Z","macos":"15.7.9","overlays":["tls-proxy"],"results":[
 {"id":"BL-OS-02","title":"Firewall","layer":"baseline","level":"MUST","status":"FAIL","evidence":"$HOME/secret-evidence","note":"host-abc"},
 {"id":"BL-OS-01","title":"FileVault","layer":"baseline","level":"MUST","status":"PASS","evidence":"FileVault: On","note":""},
 {"id":"OV-PX-01","title":"Proxy CA","layer":"overlay:tls-proxy","level":"SHOULD","status":"NA","evidence":"","note":""},
 {"id":"BL-RC-02","title":"Hook","layer":"baseline","level":"SHOULD","status":"ACCEPTED","evidence":"","note":"private reason"}
]}
EOF
  ln -s 20261016T050000Z "$DEVWARD_REPORTS/latest"
  export DEVWARD_CONTROLS="$BATS_TEST_TMPDIR/controls.json"
  cat > "$DEVWARD_CONTROLS" <<'EOF'
[
 {"id":"BL-OS-01","layer":"baseline"}, {"id":"BL-OS-02","layer":"baseline"}, {"id":"BL-RC-02","layer":"baseline"},
 {"id":"OV-PX-01","layer":"overlay:tls-proxy"}, {"id":"OV-ZZ-01","layer":"overlay:other"}
]
EOF
}
line() { grep -n -e "$1" "$2" | head -n 1 | cut -d: -f1; }  # PATTERN FILE — the first matching line's number

@test "refuses a results.json that is missing a control" {
  jq '.results |= map(select(.id != "BL-OS-01"))' "$R/results.json" > "$R/r.tmp" && mv "$R/r.tmp" "$R/results.json"
  run "$REPO/summary/build.sh" --name "Test Person"
  [ "$status" -eq 2 ]
  [[ "$output" == *"results are incomplete: run /posture again"* ]]
  [ ! -e "$R/posture-summary.md" ]
}

@test "refuses a results.json whose ids differ from the controls that apply" {
  jq '.results |= map(if .id == "BL-OS-01" then .id = "BL-XX-99" else . end)' "$R/results.json" > "$R/r.tmp" && mv "$R/r.tmp" "$R/results.json"
  run "$REPO/summary/build.sh" --name "Test Person"
  [ "$status" -eq 2 ]
  [[ "$output" == *"incomplete"* ]]
  [ ! -e "$R/posture-summary.md" ]
}

@test "refuses when the overlays name a control the results lack" {
  jq '.overlays += ["other"]' "$R/results.json" > "$R/r.tmp" && mv "$R/r.tmp" "$R/results.json"
  run "$REPO/summary/build.sh" --name "Test Person"
  [ "$status" -eq 2 ]
  [[ "$output" == *"results are incomplete"* ]]
}

@test "builds a table with ids, titles, levels and statuses: MUST before SHOULD, FAIL before ACCEPTED, NA and PASS" {
  run "$REPO/summary/build.sh" --name "Test Person"
  [ "$status" -eq 0 ]
  A="$R/posture-summary.md"
  [[ "$output" == */posture-summary.md ]]
  grep -q '| Person | Test Person |' "$A"
  grep -q '| macOS | 15 |' "$A"
  grep -q '| Standard | baseline, gold, overlay:tls-proxy |' "$A"
  [ "$(line BL-OS-02 "$A")" -lt "$(line BL-OS-01 "$A")" ]
  [ "$(line '^| BL-RC-02 | Hook' "$A")" -lt "$(line OV-PX-01 "$A")" ]
  [ "$(line BL-OS-01 "$A")" -lt "$(line '^| BL-RC-02 | Hook' "$A")" ]
  grep -q '| BL-OS-02 | Firewall | MUST | FAIL |' "$A"
}

@test "an urgent FAIL comes first, whatever its level; a set-up FAIL named by not_urgent_if does not" {
  jq '.results |= map(if .id == "OV-PX-01" then .status = "FAIL" | .evidence = "2 signs of live malware" else . end)' "$R/results.json" > "$R/r.tmp" && mv "$R/r.tmp" "$R/results.json"
  jq 'map(if .id == "OV-PX-01" then .urgent = true | .not_urgent_if = "No accepted baseline yet" else . end)' "$DEVWARD_CONTROLS" > "$R/c.tmp" && mv "$R/c.tmp" "$DEVWARD_CONTROLS"
  "$REPO/summary/build.sh" --name "Test Person"
  A="$R/posture-summary.md"; H="$R/posture-summary.html"
  [ "$(line OV-PX-01 "$A")" -lt "$(line BL-OS-02 "$A")" ]
  [ "$(line '>OV-PX-01<' "$H")" -lt "$(line '>BL-OS-02<' "$H")" ]
  jq '.results |= map(if .id == "OV-PX-01" then .evidence = "No accepted baseline yet" else . end)' "$R/results.json" > "$R/r.tmp" && mv "$R/r.tmp" "$R/results.json"
  "$REPO/summary/build.sh" --name "Test Person"
  [ "$(line BL-OS-02 "$A")" -lt "$(line OV-PX-01 "$A")" ]
}

@test "the summary says it is self-reported and not tamper-evident, and never calls itself an attestation" {
  "$REPO/summary/build.sh" --name "Test Person"
  for f in "$R/posture-summary.md" "$R/posture-summary.html"; do
    grep -q 'Posture summary (self-reported)' "$f"
    grep -q 'not tamper-evident' "$f"
    ! grep -qi 'attestation' "$f"
  done
}

@test "the summary names the devward release, its commit and a hash of the controls file" {
  D="$BATS_TEST_TMPDIR/dw"; release_tree "$D" summary checks/lib templates
  run env DEVWARD_REPO="$D" "$D/summary/build.sh" --name "Test Person"
  [ "$status" -eq 0 ]
  A="$R/posture-summary.md"; H="$R/posture-summary.html"
  sha="$(git -C "$D" rev-parse HEAD)"; ctl="$(shasum -a 256 "$DEVWARD_CONTROLS" | cut -d' ' -f1)"
  grep -q '| devward version | v0.1.0 |' "$A"
  grep -q "| devward commit | $sha |" "$A"
  grep -q "| Controls (SHA-256) | $ctl |" "$A"
  grep -q "$sha" "$H"; grep -q "$ctl" "$H"; grep -q 'v0.1.0' "$H"
  echo '# edited' >> "$D/summary/name.sh"
  env DEVWARD_REPO="$D" "$D/summary/build.sh" --name "Test Person"
  grep -q '| devward version | not a signed release: it has local changes to its files |' "$A"
}

@test "the summary claims no release for a tag nobody signed" {
  D="$BATS_TEST_TMPDIR/dw"; mkdir -p "$D"; git -C "$D" init -q -b main
  cp -R "$REPO/summary" "$REPO/templates" "$D/"; mkdir -p "$D/checks"; cp -R "$REPO/checks/lib" "$D/checks/"
  commit "$D"; git -C "$D" tag v9.9.9
  env DEVWARD_REPO="$D" "$D/summary/build.sh" --name "Test Person"
  A="$R/posture-summary.md"
  grep -q '| devward version | not a signed release: it is not on a signed release |' "$A"
  ! grep -q 'v9.9.9' "$A"
}

@test "never includes evidence, notes of other statuses or paths" {
  "$REPO/summary/build.sh" --name "Test Person"
  A="$R/posture-summary.md"
  [ "$(grep -c -e secret-evidence -e host-abc -e "$HOME" "$A")" = 0 ]
}

@test "lists the reason for each ACCEPTED item" {
  "$REPO/summary/build.sh" --name "Test Person"
  A="$R/posture-summary.md"
  grep -q '^## Accepted decisions' "$A"
  grep -q '^| BL-RC-02 | private reason |' "$A"
}

@test "writes posture-summary.html with an expandable reason on ACCEPTED rows" {
  "$REPO/summary/build.sh" --name "Test Person"
  H="$R/posture-summary.html"
  grep -q 'Test Person' "$H"
  grep -q 'aria-controls="r-BL-RC-02"' "$H"
  grep -q '<tr class="why-row" id="r-BL-RC-02" hidden><td></td><td colspan="3"><span class="why-l">Reason</span>private reason</td></tr>' "$H"
  [ "$(grep -c -e secret-evidence -e host-abc -e "$HOME" "$H")" = 0 ]
  ! grep -q '{{' "$H"
}

@test "posture-summary.html escapes names, titles and reasons" {
  jq '.results[3].note = "<b>x</b> & \"q\"" | .results[0].title = "<script>1</script>"' "$R/results.json" > "$R/r2.json"
  "$REPO/summary/build.sh" --name '<i>Test</i>' "$R/r2.json"
  H="$R/posture-summary.html"
  ! grep -q -e '<i>Test' -e '<script>1' -e '<b>x' "$H"
  grep -q '&lt;i&gt;Test&lt;/i&gt;' "$H"
  grep -q '&lt;b&gt;x&lt;/b&gt; &amp; &quot;q&quot;' "$H"
}

@test "needs a name" {
  run "$REPO/summary/build.sh"
  [ "$status" -eq 2 ]
}

@test "--name without a value is a usage error, not a hang" {
  run perl -e 'alarm 5; exec @ARGV' "$REPO/summary/build.sh" --name
  [ "$status" -eq 2 ]
}

@test "a malformed results.json fails and writes no summary" {
  for bad in '{}' 'not json'; do
    printf '%s\n' "$bad" > "$R/results.json"
    run "$REPO/summary/build.sh" --name "Test Person"
    [ "$status" -ne 0 ]
    [ ! -e "$R/posture-summary.md" ]
  done
}
