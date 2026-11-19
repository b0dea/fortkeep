#!/bin/bash
# Prints the one question the person answers to approve a fix, an undo, an accepted control or a new private folder, as
# the JSON object the question tool takes (AskUserQuestion, OpenCode's question). Pass it unchanged: the approval hook
# records an answer only to exactly this question, naming what the change does, with exactly these options.
# Usage: checks/ask.sh ID apply|undo | checks/ask.sh ID accept "REASON" | checks/ask.sh private add FOLDER
. "$(dirname "$0")/lib/common.sh"
CONTROLS="${DEVWARD_CONTROLS:-$DEVWARD_REPO/controls/controls.json}"
usage() { echo "usage: $0 ID apply|undo | $0 ID accept \"REASON\" | $0 private add FOLDER" >&2; exit 2; }
if [ "${1:-} ${2:-}" = "private add" ]; then
  # The question names the folder exactly as checks/private.sh add will take it, and the approval hook ties the answer
  # to that folder.
  [ $# -eq 3 ] || usage
  f="$(devward_private_folder "$3")" || { echo "use an absolute path, or one starting with ~/, without . or .. in it" >&2; exit 2; }
  if devward_private_refused "$f"; then
    echo "that folder is /, your home folder, a folder above it, or devward's own folder: if it must be private, add it yourself in the Terminal app" >&2
    exit 2
  fi
  jq -n --arg f "$f" '{question: "Add \"\($f)\" to the private list? Every scan skips that folder from now on, and only you can take it off, in the Terminal app.",
    header: "Private", multiSelect: false,
    options: [{label: "Add private folder", description: "Skip that folder in every scan."},
              {label: "Don'"'"'t add", description: "Scans keep reading it."}]}'
  exit
fi
case "${2:-}" in
  apply|undo) [ $# -eq 2 ] || usage ;;
  # The question names the reason, and the approval hook ties the answer to it: the words recorded as the person's are
  # the ones they saw.
  accept) [ $# -eq 3 ] || usage
    devward_accept_reason "$3" || { echo "give the reason as one line of at most 300 characters, without backslashes" >&2; exit 2; } ;;
  *) usage ;;
esac
printf '%s\n' "$1" | grep -Eq '^(BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}$' || usage
jq -e --arg id "$1" --arg act "$2" --arg r "${3:-}" '
  map(select(.id == $id)) | first // error("unknown control")
  | if $act != "accept" and (.fix // "") == "" then error("no fix script") else . end
  | "\(.id) (\(.title))" as $what
  | if $act == "apply" then
      {question: "Apply the fix for \($what)? It runs fixes/macos/\(.id).sh apply, which you can undo.",
       options: [{label: "Apply \(.id)", description: "Make this change now."},
                 {label: "Skip", description: "Leave \(.id) as it is and go to the next one."},
                 {label: "Stop fixing", description: "Stop here. Nothing else changes."}]}
    elif $act == "undo" then
      {question: "Undo the fix for \($what)? It runs fixes/macos/\(.id).sh undo, which puts back what the fix changed.",
       options: [{label: "Undo \(.id)", description: "Put it back as it was before the fix."},
                 {label: "Keep it", description: "Leave the fix in place."}]}
    else
      {question: "Keep \($what) unmet as your own decision, with the reason \"\($r)\"? It shows as ACCEPTED, with that reason, from the next run.",
       options: [{label: "Accept \(.id)", description: "Record this decision."},
                 {label: "Don'"'"'t accept", description: "It stays a FAIL."}]}
    end
  | {question, header: $id, options, multiSelect: false}' "$CONTROLS" 2>/dev/null \
  || { echo "no such control with a fix to ask about: $1 $2" >&2; exit 2; }
