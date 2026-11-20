#!/bin/bash
# An "Apply <ID>", "Undo <ID>", "Accept <ID>" or "Add private folder" from the person mints a one-use approval token.
# Claude Code: PostToolUse on AskUserQuestion, picked in exactly the question checks/ask.sh prints for that action.
# OpenCode: its plugin passes the question tool's questions and answers in the same shape. Codex has no question
# tool outside Plan mode: UserPromptSubmit, when the whole typed message is the answer ("Add private folder <path>",
# "Accept <ID> <reason>"). A private-folder token is tied to the one folder named, an accept token to the reason.
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$HERE/../.." && pwd)}"
. "$HERE/../../checks/lib/agent.sh"
input="$(cat)"
# Only the agent this hook runs in may be above it. In an agent another agent started (codex exec, claude -p or
# opencode run, inside a session) the first agent writes the "person's" messages. /bin/ps is fixed on purpose.
if [ "$(fortkeep_agent_runs /bin/ps)" -gt 1 ]; then
  echo "fortkeep: no approval recorded: this agent was started by another agent" >&2; exit 0
fi
# A private folder and an accept reason are named in the question; Codex has none, so there the typed answer names
# them after the words.
RE='^((Apply|Undo|Accept) (BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}|Add private folder)$'
TYPED='^((Apply|Undo) (BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}|Accept (BL|GD|OV)-[A-Z]{2,4}-[0-9]{2} [^[:cntrl:]]+|Add private folder [^[:cntrl:]]+)$'
# One line per answer that names an action: the index of its question ("-" for a typed message), then the answer.
# Whole-string match inside jq: a multi-line answer never reaches the line loop. A subagent's prompt (agent_id or
# agent_type set) is written by the model, never by the person.
ANSWERS='def ok($r): select(type == "string" and (contains("\n") | not) and test($r));
  if .hook_event_name == "UserPromptSubmit" then
    (if ((.agent_id // "") + (.agent_type // "")) == "" then (.prompt // "" | gsub("^[[:space:]]+|[[:space:]]+$"; "") | ok($typed) | "- \(.)") else empty end)
  else
    (.tool_response.answers // {}) as $a
    | (.tool_input.questions // []) | to_entries[]
    | .key as $i | ($a[.value.question // ""] // empty) | ok($re) | "\($i) \(.)"
  end'
# The folder a private-folder question names (checks/ask.sh private add FOLDER prints it between quotes).
folder_of() { jq -r '.question // "" | strings | capture("^Add \"(?<f>.*)\" to the private list\\? ").f // empty'; }
# The reason an accept question names (checks/ask.sh ID accept REASON prints it between quotes).
reason_of() { jq -r '.question // "" | strings | capture(" with the reason \"(?<r>.*)\"\\? It shows as ACCEPTED").r // empty'; }
# The question as the person saw it must be the canonical one: its text, and exactly its options and descriptions.
SAME='.tool_input.questions[$i] as $q
  | $q.question == $c.question and ([$q.options[]? | .label] == [$c.options[].label])
    and ([$q.options[]? | .description] == [$c.options[].description]) and (($q.multiSelect // $q.multiple // false) == false)'
jq -r --arg re "$RE" --arg typed "$TYPED" "$ANSWERS" 2>/dev/null <<<"$input" | while read -r idx answer; do
  ask=()
  case "$answer" in
    "Add private folder"*)
      id=private; act=add
      if [ "$idx" = - ]; then folder="${answer#Add private folder }"
      else folder="$(jq -c --argjson i "$idx" '.tool_input.questions[$i]' <<<"$input" | folder_of)"; fi
      [ -n "$folder" ] || continue
      ask=(private add "$folder") ;;
    *) case "${answer%% *}" in Apply) act=apply ;; Undo) act=undo ;; Accept) act=accept ;; *) continue ;; esac
      rest="${answer#* }"; id="${rest%% *}"
      printf '%s' "$id" | grep -Eq '^(BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}$' || continue
      ask=("$id" "$act")
      if [ "$act" = accept ]; then
        if [ "$idx" = - ]; then reason="${rest#"$id" }"
        else reason="$(jq -c --argjson i "$idx" '.tool_input.questions[$i]' <<<"$input" | reason_of)"; fi
        [ -n "$reason" ] || continue
        ask+=("$reason")
      fi ;;
  esac
  # checks/ask.sh prints the question for the folder as checks/private.sh takes it, or refuses one it never asks about;
  # likewise for a reason.
  if [ "$idx" != - ] || [ "$id" = private ] || [ "$act" = accept ]; then
    c="$("$HERE/../../checks/ask.sh" "${ask[@]}" 2>/dev/null)" || continue
  fi
  if [ "$idx" != - ]; then
    jq -e --argjson c "$c" --argjson i "$idx" "$SAME" >/dev/null 2>&1 <<<"$input" || continue
  fi
  mkdir -p "$REPO/reports/.approvals"
  # A private-folder token holds its folder, which checks/private.sh add compares, and an accept token its reason,
  # which checks/accept.sh compares; the others only need their time.
  if [ "$id" = private ]; then folder_of <<<"$c" > "$REPO/reports/.approvals/$id.$act"
  elif [ "$act" = accept ]; then printf '%s\n' "$reason" > "$REPO/reports/.approvals/$id.$act"
  else date +%s > "$REPO/reports/.approvals/$id.$act"; fi
done
# A no to the canonical question for an action withdraws any token still waiting for it: the person changed their mind.
# One line per such answer: the index of its question, its header (the control's ID, or Private), then the answer.
NO='(.tool_response.answers // {}) as $a
  | (.tool_input.questions // []) | to_entries[]
  | .key as $i | (.value.header // "") as $h | ($a[.value.question // ""] // empty)
  | select(type == "string" and IN("Skip", "Stop fixing", "Keep it", "Don'\''t accept", "Don'\''t add"))
  | "\($i)\t\($h)\t\(.)"'
jq -r "$NO" 2>/dev/null <<<"$input" | while IFS="$(printf '\t')" read -r idx id answer; do
  q="$(jq -c --argjson i "$idx" '.tool_input.questions[$i]' <<<"$input")"
  case "$answer" in
    "Don't add") [ "$id" = Private ] || continue; ask=(private add "$(folder_of <<<"$q")") ;;
    "Don't accept") ask=("$id" accept "$(reason_of <<<"$q")") ;;
    "Keep it") ask=("$id" undo) ;;
    *) ask=("$id" apply) ;;
  esac
  [ "${ask[0]}" = private ] || printf '%s' "$id" | grep -Eq '^(BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}$' || continue
  c="$("$HERE/../../checks/ask.sh" "${ask[@]}" 2>/dev/null)" || continue
  jq -e --argjson c "$c" --argjson i "$idx" "$SAME" >/dev/null 2>&1 <<<"$input" || continue
  rm -f "$REPO/reports/.approvals/${ask[0]}.${ask[1]}"
done
exit 0
