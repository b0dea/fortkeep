#!/bin/bash
# Validates controls.json and checks it is up to date with the YAML sources.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
ci/build-controls.sh "$tmp"
if ! cmp -s "$tmp" controls/controls.json; then
  echo "controls.json is stale: run make controls" >&2; exit 1
fi
# Non-string values fail their rule instead of crashing jq.
errors="$(jq -r '
  def bad(m): "\(.id // "?"): \(m)";
  def str(f): (f | type) == "string";
  (group_by(.id)[] | select(length > 1) | .[0] | bad("duplicate id")),
  (.[] | select((str(.id) and (.id | test("^(BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}$"))) | not) | bad("id format")),
  (.[] | select((str(.layer) and (.layer | test("^(baseline|gold|overlay:[a-z0-9-]+)$"))) | not) | bad("layer")),
  (.[] | select((.level // "") | IN("MUST","SHOULD","NICE") | not) | bad("level")),
  (.[] | select((.risk // "") | IN("low","medium","high") | not) | bad("risk")),
  (.[] | select((.title // "") == "") | bad("title")),
  (.[] | select((.fix_needs_admin | type) != "boolean") | bad("fix_needs_admin must be true or false")),
  (.[] | select(.layer == "baseline" and ((str(.source) and (.source | test("^§[0-9]+$"))) | not)) | bad("baseline control needs source §N")),
  (.[] | select((str(.check) and .check != "") | not) | bad("check path must be a non-empty string")),
  (.[] | select((str(.teach) and .teach != "") | not) | bad("teach path must be a non-empty string")),
  (.[] | select(.fix != null and ((str(.fix) and .fix != "") | not)) | bad("fix path must be null or a non-empty string")),
  (.[] | select(has("urgent") and (.urgent | type) != "boolean") | bad("urgent must be true or false")),
  (.[] | select(.urgent == true and .fix != null) | bad("an urgent control can'"'"'t have a fix script")),
  (.[] | select(has("not_urgent_if") and ((str(.not_urgent_if) and .not_urgent_if != "") | not)) | bad("not_urgent_if must be a non-empty string")),
  (.[] | select(has("mscp") and (((.mscp | type) == "array" and (.mscp | length) > 0 and all(.mscp[]; type == "string" and test("^[a-z0-9_]+$"))) | not)) | bad("mscp must be a list of mSCP rule ids")),
  (.[] | select(((.alternatives | type) == "array" and all(.alternatives[]; type == "string" and . != "")) | not) | bad("alternatives must be a list of names")),
  (.[] | select((.layer | strings | startswith("overlay:")) and ((str(.overlay.title) and .overlay.title != "" and str(.overlay.pick_if) and .overlay.pick_if != "") | not)) | bad("overlay needs a title and a pick_if line")),
  (.[] | select(has("timeout") and ((.timeout | type) != "number" or .timeout != (.timeout | floor) or .timeout < 1 or .timeout > 600)) | bad("timeout must be whole seconds from 1 to 600"))
' controls/controls.json)"
# Path strings are read line by line so spaces and empties are not word-split.
paths="$(jq -r '.[] | .check, .teach, .fix | select(type == "string" and . != "")' controls/controls.json)"
while IFS= read -r f; do
  if [ -n "$f" ] && [ ! -f "$f" ]; then errors="$errors"$'\n'"missing file: $f"; fi
done <<<"$paths"
errors="$(printf '%s\n' "$errors" | sed '/^$/d')"
if [ -n "$errors" ]; then echo "$errors" >&2; exit 1; fi
echo "controls OK ($(jq length controls/controls.json))"
