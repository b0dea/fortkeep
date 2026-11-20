load helpers

# The OpenCode plugin, loaded by Node (which strips the TypeScript types) and driven like OpenCode drives it,
# against the real guard scripts. The worktree is a scratch tree linked to this repo's hooks and libraries,
# so approval tokens land in scratch.
setup() {
  setup_env
  node -e 'process.exit(+process.versions.node.split(".")[0] >= 22 ? 0 : 1)' 2>/dev/null || skip "needs Node 22 or later"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  ln -s "$REPO/.claude" "$WT/.claude"; ln -s "$REPO/checks" "$WT/checks"
  cat > "$BATS_TEST_TMPDIR/drive.mjs" <<'EOF'
const [plugin, wt, step, json] = process.argv.slice(2)
const { Fortkeep } = await import(plugin)
const hooks = await Fortkeep({ directory: wt, worktree: wt })
const call = JSON.parse(json ?? "{}")
try {
  if (step === "system") {
    const out = { system: [] }
    await hooks["experimental.chat.system.transform"]({}, out)
    console.log(out.system.join("\n"))
  } else if (step === "before") {
    await hooks["tool.execute.before"]({ tool: call.tool, callID: "c1" }, { args: call.args })
    console.log("allowed")
  } else {
    await hooks["tool.execute.after"]({ tool: call.tool, callID: "c1", args: call.args }, { metadata: call.metadata })
  }
} catch (e) {
  console.log(`blocked: ${e.message}`)
  process.exit(2)
}
EOF
}
drive() { node --experimental-strip-types "$BATS_TEST_TMPDIR/drive.mjs" "$REPO/.opencode/plugins/fortkeep.ts" "$WT" "$@" 2>/dev/null; }

@test "opencode: the session-start message reaches the model" {
  person_session
  run drive system; [ "$status" -eq 0 ]; [[ "$output" == *"fortkeep checks and hardens this Mac"* ]]
}
@test "opencode: a person's session runs only fortkeep's scripts and reads only the checkout" {
  person_session
  run drive before '{"tool":"bash","args":{"command":"checks/run.sh --only BL-OS-01"}}'; [ "$status" -eq 0 ]
  run drive before '{"tool":"bash","args":{"command":"ls"}}'; [ "$status" -eq 2 ]
  run drive before '{"tool":"bash","args":{"command":"./fixes/macos/BL-RC-01.sh apply"}}'; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg w "$HOME" '{tool:"bash", args:{command:"checks/run.sh", workdir:$w}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg f "$WT/controls.json" '{tool:"read", args:{filePath:$f}}')"; [ "$status" -eq 0 ]
  run drive before "$(jq -cn --arg f "$HOME/notes.txt" '{tool:"read", args:{filePath:$f}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg f "$WT/reports/config.json" '{tool:"write", args:{filePath:$f, content:"{}"}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg p "$WT" '{tool:"list", args:{path:$p}}')"; [ "$status" -eq 2 ]
}
@test "opencode: sudo and edits outside the repo are blocked, ordinary calls pass" {
  run drive before '{"tool":"bash","args":{"command":"sudo softwareupdate -l"}}'; [ "$status" -eq 2 ]; [[ "$output" == *"sudo"* ]]
  run drive before '{"tool":"bash","args":{"command":"checks/run.sh --only BL-OS-01"}}'; [ "$status" -eq 0 ]
  run drive before "$(jq -cn --arg f "$HOME/.zshrc" '{tool:"edit", args:{filePath:$f, oldString:"a", newString:"b"}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg f "$WT/reports/notes.md" '{tool:"write", args:{filePath:$f, content:"x"}}')"; [ "$status" -eq 0 ]
  run drive before "$(jq -cn --arg p "$(printf '*** Begin Patch\n*** Add File: %s/.zshrc\n+x\n*** End Patch' "$HOME")" '{tool:"apply_patch", args:{patchText:$p}}')"
  [ "$status" -eq 2 ]
}
@test "opencode: a private folder is blocked for reads and searches" {
  mkdir -p "$HOME/Private"; printf '%s\n' "$HOME/Private" > "$FORTKEEP_PRIVATE_PATHS"
  run drive before "$(jq -cn --arg f "$HOME/Private/a.txt" '{tool:"read", args:{filePath:$f}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg p "$HOME" '{tool:"grep", args:{pattern:"x", path:$p}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg f "$WT/reports/notes.md" '{tool:"read", args:{filePath:$f}}')"; [ "$status" -eq 0 ]
  # the folder-listing tool is a read of that folder
  run drive before "$(jq -cn --arg p "$HOME/Private" '{tool:"list", args:{path:$p}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg p "$HOME" '{tool:"list", args:{path:$p}}')"; [ "$status" -eq 2 ]
  run drive before "$(jq -cn --arg p "$WT/reports" '{tool:"list", args:{path:$p}}')"; [ "$status" -eq 0 ]
}
@test "opencode: a tool with no guard is refused unless it touches no file" {
  run drive before "$(jq -cn --arg p "$HOME/Private" '{tool:"some_mcp_lister", args:{path:$p}}')"
  [ "$status" -eq 2 ]; [[ "$output" == *"no guard here"* ]]
  run drive before '{"tool":"task","args":{"prompt":"list ~/Private"}}'; [ "$status" -eq 2 ]
  run drive before '{"tool":"todowrite","args":{"todos":[]}}'; [ "$status" -eq 0 ]
  run drive before '{"tool":"question","args":{"questions":[]}}'; [ "$status" -eq 0 ]
}
@test "opencode: web fetch and search are refused in a person's session, not in a development one" {
  run drive before '{"tool":"webfetch","args":{"url":"https://example.com/"}}'; [ "$status" -eq 0 ]
  person_session
  run drive before '{"tool":"webfetch","args":{"url":"https://example.com/?q=x"}}'; [ "$status" -eq 2 ]; [[ "$output" == *web* ]]
  run drive before '{"tool":"websearch","args":{"query":"x"}}'; [ "$status" -eq 2 ]
}
@test "opencode: only an Apply <ID> the person picked in the canonical question mints a token" {
  q="$("$REPO/checks/ask.sh" BL-RC-01 apply | jq -c 'del(.multiSelect) | .multiple = false')"  # as OpenCode's tool takes it
  ans() { jq -cn --argjson q "$q" --arg t "$1" --arg a "$2" '{tool:$t, args:{questions:[$q]}, metadata:{answers:[[$a]]}}'; }
  run drive after "$(ans question Skip)"; [ "$status" -eq 0 ]
  [ ! -d "$WT/reports/.approvals" ] || [ -z "$(ls "$WT/reports/.approvals")" ]
  run drive after "$(ans bash "Apply BL-RC-01")"; [ "$status" -eq 0 ]
  [ ! -e "$WT/reports/.approvals/BL-RC-01.apply" ]
  run drive after "$(ans question "Apply BL-RC-01" | jq -c '.args.questions[0].question = "Pick one"')"; [ "$status" -eq 0 ]
  [ ! -e "$WT/reports/.approvals/BL-RC-01.apply" ]
  run drive after "$(ans question "Apply BL-RC-01")"; [ "$status" -eq 0 ]
  [ -f "$WT/reports/.approvals/BL-RC-01.apply" ]
}
