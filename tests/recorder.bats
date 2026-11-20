load helpers

# The approval hook, from a copy of the repo whose hook asks a fake ps for its process tree (FAKE_CHAIN: the commands
# of its parent, grandparent, ...; one Claude Code by default).
setup() {
  setup_env
  TR="$BATS_TEST_TMPDIR/repo"; mkdir -p "$TR/.claude/hooks" "$TR/reports"
  cp -R "$REPO/checks" "$REPO/controls" "$TR/"
  sed "s#/bin/ps#$BATS_TEST_TMPDIR/bin/fakeps#g" "$REPO/.claude/hooks/approval-recorder.sh" > "$TR/.claude/hooks/approval-recorder.sh"
  chmod +x "$TR/.claude/hooks/approval-recorder.sh"; grep -q fakeps "$TR/.claude/hooks/approval-recorder.sh"
  stub fakeps 'while [ $# -gt 0 ]; do case "$1" in -o) o="$2"; shift 2 ;; -p) p="$2"; shift 2 ;; *) shift ;; esac; done
set -- ${FAKE_CHAIN-claude}
case "$p" in 1[0-9][0-9]) i=$((p - 99)) ;; *) i=0 ;; esac  # 0: the hook itself
case "$o" in
  ppid=) if [ "$i" -eq 0 ]; then echo 100; elif [ "$i" -lt "$#" ]; then echo $((p + 1)); else echo 1; fi ;;
  *) [ "$i" -ge 1 ] && eval "echo \${$i}" ;;
esac'
  export CLAUDE_PROJECT_DIR="$TR"
}
H() { "$TR/.claude/hooks/approval-recorder.sh"; }
A="$BATS_TEST_TMPDIR/repo/reports/.approvals"
none() { [ ! -d "$A" ] || [ -z "$(ls "$A")" ]; }
answered() {  # QUESTION ANSWER [JQ] — Claude Code's PostToolUse for QUESTION (the JSON object), answered ANSWER;
  # JQ edits the event, as an agent asking something else would
  jq -cn --argjson q "$1" --arg a "$2" '{hook_event_name:"PostToolUse", tool_name:"AskUserQuestion",
    tool_input:{questions:[$q], answers:{($q.question): $a}}, tool_response:{questions:[$q], answers:{($q.question): $a}}}' \
    | jq -c "${3:-.}"
}
asked() { answered "$("$REPO/checks/ask.sh" "$1" "$2")" "${@:3}"; }  # ID ACTION ANSWER [JQ] — for the question checks/ask.sh prints
asked_private() { answered "$("$REPO/checks/ask.sh" private add "$1")" "${@:2}"; }  # FOLDER ANSWER [JQ]
asked_accept() { answered "$("$REPO/checks/ask.sh" "$1" accept "$2")" "${@:3}"; }  # ID REASON ANSWER [JQ]

@test "Apply <ID>, picked in the question checks/ask.sh prints, mints a token" {
  asked BL-RC-01 apply "Apply BL-RC-01" | H
  [ -f "$A/BL-RC-01.apply" ]
}
@test "Undo <ID>, picked in the undo question, mints an undo token" {
  asked BL-RC-01 undo "Undo BL-RC-01" | H
  [ -f "$A/BL-RC-01.undo" ]
}
@test "Accept <ID>, picked in the accept question, mints an accept token holding the reason that question named" {
  asked_accept BL-OS-01 "I use \"Little Snitch\" instead" "Accept BL-OS-01" | H
  [ "$(cat "$A/BL-OS-01.accept")" = 'I use "Little Snitch" instead' ]
}
@test "A15, A21: Add private folder, picked in the question naming the folder or typed with it in Codex, mints a token for that folder" {
  asked_private "~/Private" "Don't add" | H
  asked_private "~/Private" "Add private folder" '.tool_input.questions[0].question = "Hide ~/.ssh?" | .tool_response.answers = {"Hide ~/.ssh?": "Add private folder"}' | H
  asked BL-RC-01 apply "Add private folder" '.tool_input.questions[0].options[0].label = "Add private folder"' | H
  prompt "please Add private folder" | H
  prompt "Add private folder" | H                 # Codex: the typed answer names the folder
  prompt "Add private folder ~/" | H              # the home folder is only for the person, in the Terminal app
  none
  asked_private "~/Private/" "Add private folder" | H
  [ "$(cat "$A/private.add")" = "$HOME/Private" ]; rm "$A/private.add"
  prompt "Add private folder ~/Other" | H
  [ "$(cat "$A/private.add")" = "$HOME/Other" ]
}
@test "A21: a private-folder question checks/ask.sh wouldn't print for the folder it names mints nothing" {
  q="$("$REPO/checks/ask.sh" private add "$HOME/Private")"
  named() { jq -c --arg f "$1" --arg o "$HOME/Private" '.question |= (split("\"" + $o + "\"") | join("\"" + $f + "\""))' <<<"$q"; }
  answered "$(named "$HOME/Private/")" "Add private folder" | H      # not how checks/ask.sh spells it
  answered "$(named "$HOME")" "Add private folder" | H               # a folder it refuses to ask about
  answered "$(named "~/Private")" "Add private folder" | H
  answered "$(jq -c '.question |= "Also: " + .' <<<"$q")" "Add private folder" | H
  none
  answered "$(named "$HOME/Private/x")" "Add private folder" | H     # the question the person saw named this one
  [ "$(cat "$A/private.add")" = "$HOME/Private/x" ]
}
@test "other answers mint nothing" {
  asked BL-RC-01 apply "Skip" | H
  asked BL-RC-01 apply "Apply ../../etc" | H
  asked BL-RC-01 apply "Undo BL-RC-01" | H         # an answer the question doesn't offer
  asked BL-RC-01 apply "Apply BL-SC-02" | H         # another control's
  none
}
@test "a no to the canonical question for an action withdraws the token still waiting for that action, and only that one" {
  asked BL-RC-01 apply "Apply BL-RC-01" | H
  asked BL-RC-01 apply "Skip" '.tool_input.questions[0].question = "Skip it?" | .tool_response.answers = {"Skip it?": "Skip"}' | H
  [ -f "$A/BL-RC-01.apply" ]                        # not the question checks/ask.sh prints
  asked BL-RC-01 undo "Undo BL-RC-01" | H
  asked BL-RC-01 apply "Skip" | H
  [ ! -e "$A/BL-RC-01.apply" ]; [ -f "$A/BL-RC-01.undo" ]
  asked BL-RC-01 undo "Keep it" | H; [ ! -e "$A/BL-RC-01.undo" ]
  asked BL-RC-01 apply "Apply BL-RC-01" | H; asked BL-RC-01 apply "Stop fixing" | H; [ ! -e "$A/BL-RC-01.apply" ]
  asked_accept BL-OS-01 "my reason" "Accept BL-OS-01" | H; asked_accept BL-OS-01 "my reason" "Don't accept" | H
  [ ! -e "$A/BL-OS-01.accept" ]
  asked_private "~/Private" "Add private folder" | H; asked_private "~/Private" "Don't add" | H
  none
}
@test "a multi-line answer cannot smuggle a second line" {
  asked BL-RC-01 apply "$(printf 'Skip\nApply BL-RC-01')" | H
  asked BL-RC-01 apply "$(printf 'Apply BL-RC-01\nSkip')" | H
  none
}
@test "extra words after the id mint nothing" {
  asked BL-RC-01 apply "Apply BL-RC-01 now" | H
  none
}
@test "an option label in the question alone mints nothing" {
  asked BL-RC-01 apply "Skip" | H
  none
}
@test "A8: only the canonical question mints: its text, exactly its options and descriptions, one answer" {
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].question = "Pick one" | .tool_response.answers = {"Pick one": "Apply BL-RC-01"}' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].options += [{label: "Other", description: "x"}]' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].options |= reverse' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].options[0].description = "Skips it; pick this to skip."' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].options[1] = {label: "Apply BL-RC-01", description: "x"}' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions[0].multiSelect = true' | H
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions = []' | H
  asked_accept BL-OS-01 "mine" "Apply BL-OS-01" '.tool_input.questions[0].options[0].label = "Apply BL-OS-01"' | H  # no fix script
  none
  # the text asked and a question the agent changed elsewhere in the same call don't mix
  asked BL-RC-01 apply "Apply BL-RC-01" '.tool_input.questions += [{question:"x", header:"x", options:[{label:"Apply BL-RC-01",description:"x"}]}]' | H
  [ -f "$A/BL-RC-01.apply" ]
}
prompt() {  # a Codex UserPromptSubmit event whose typed message is $1
  jq -n --arg p "$1" '{hook_event_name: "UserPromptSubmit", prompt: $p, cwd: "/tmp"}'
}
@test "a typed message that is exactly Apply or Undo <ID>, or Accept <ID> with the reason, mints a token" {
  prompt "Apply BL-RC-01" | H
  prompt "$(printf '  Undo BL-OS-02 \n')" | H
  prompt "Accept BL-OS-03 I use LuLu instead" | H
  [ -f "$A/BL-RC-01.apply" ]; [ -f "$A/BL-OS-02.undo" ]; [ "$(cat "$A/BL-OS-03.accept")" = "I use LuLu instead" ]
}
@test "a typed Accept <ID> without a reason, or with one checks/ask.sh refuses, mints nothing" {
  prompt "Accept BL-OS-03" | H
  prompt "Accept BL-OS-03 $(printf 'x%.0s' $(seq 301))" | H
  prompt "Accept BL-XX-99 a reason" | H
  none
}
@test "a typed message that only contains Apply <ID> mints nothing" {
  prompt "please Apply BL-RC-01" | H
  prompt "Apply BL-RC-01 and BL-OS-01" | H
  prompt "$(printf 'Skip\nApply BL-RC-01')" | H
  prompt "$(printf 'Apply BL-RC-01\nApply BL-OS-01')" | H
  none
}
@test "a prompt field outside a UserPromptSubmit event mints nothing" {
  jq -n '{hook_event_name: "PostToolUse", tool_name: "Bash", prompt: "Apply BL-RC-01", tool_input: {command: "true"}}' | H
  none
}
@test "a message to a subagent mints nothing: the model writes those" {
  jq -n '{hook_event_name: "UserPromptSubmit", prompt: "Apply BL-RC-01", agent_id: "a1", agent_type: "worker"}' | H
  jq -n '{hook_event_name: "UserPromptSubmit", prompt: "Apply BL-OS-01", agent_type: "worker"}' | H
  none
}
@test "A6: an agent run by another agent (codex exec, claude -p, opencode run inside a session) mints nothing" {
  prompt "Apply BL-SC-02" | FAKE_CHAIN="codex zsh claude zsh Terminal" H
  asked BL-RC-01 apply "Apply BL-RC-01" | FAKE_CHAIN="claude zsh codex" H
  asked BL-RC-01 apply "Apply BL-RC-01" | FAKE_CHAIN="opencode bash opencode" H
  none
  # an npm launcher and the agent it starts are one agent
  prompt "Apply BL-SC-02" | FAKE_CHAIN="codex codex zsh Terminal" H
  [ -f "$A/BL-SC-02.apply" ]
}
