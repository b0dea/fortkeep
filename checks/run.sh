#!/bin/bash -p
# Runs every applicable check and writes reports/<run>/results.json.
# Usage: checks/run.sh [--only ID]... [--timeout SECONDS] [--weekly]
# Started as `bash run.sh`: start again in privileged mode, which ignores BASH_ENV, ENV and exported functions.
case $- in *p*) ;; *) exec /usr/bin/env -u BASH_ENV -u ENV /bin/bash -p "$0" "$@" ;; esac
case "$0" in */*) . "${0%/*}/lib/common.sh" ;; *) . ./lib/common.sh ;; esac
. "$FORTKEEP_LIB_DIR/apps.sh"
fortkeep_clean_start "$0" "$@"
export FORTKEEP_USER_PATH
CONTROLS="${FORTKEEP_CONTROLS:-$FORTKEEP_REPO/controls/controls.json}"
CONFIG="${FORTKEEP_CONFIG:-$FORTKEEP_REPORTS/config.json}"
ACCEPTED="${FORTKEEP_ACCEPTED:-$FORTKEEP_REPO/accepted.json}"
TIMEOUT=20
ONLY=""
usage="usage: $0 [--only ID]... [--timeout SECONDS] [--weekly] [--long]"
unset FORTKEEP_LONG_RUN  # only --long sets it, even where the environment is kept (the tests)
while [ $# -gt 0 ]; do
  case "$1" in
    --only) [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }; ONLY="$ONLY $2"; shift 2 ;;
    --timeout) [ $# -ge 2 ] || { echo "$usage" >&2; exit 2; }; TIMEOUT="$2"; shift 2 ;;
    --weekly) FORTKEEP_WEEKLY_RUN=1; export FORTKEEP_WEEKLY_RUN; shift ;;
    --long) FORTKEEP_LONG_RUN=1; export FORTKEEP_LONG_RUN; shift ;;
    *) echo "$usage" >&2; exit 2 ;;
  esac
done
# The weekly job (weekly.sh passes --weekly) runs while KnockKnock or Spotlight load the Mac: every limit triples,
# and shell probes get 30 s unless the caller chose a value.
# A long run (fortkeep check typed at a keyboard, which can wait) triples them too; an agent's shell call can't wait.
factor=1
if [ -n "${FORTKEEP_WEEKLY_RUN:-}" ]; then factor=3; FORTKEEP_SHELL_TIMEOUT="${FORTKEEP_SHELL_TIMEOUT:-30}"; export FORTKEEP_SHELL_TIMEOUT; fi
[ -z "${FORTKEEP_LONG_RUN:-}" ] || factor=3

jq -e 'type == "array"' "$CONTROLS" >/dev/null 2>&1 || { echo "controls file missing or not a JSON array: $CONTROLS" >&2; exit 2; }
overlays='[]'
if [ -f "$CONFIG" ]; then
  overlays="$(jq -c '.overlays // []' "$CONFIG" 2>/dev/null)" || { echo "config.json is not valid JSON" >&2; exit 2; }
  jq -e 'type == "array" and all(.[]; type == "string")' >/dev/null 2>&1 <<<"$overlays" \
    || { echo "config.json overlays must be a list of names" >&2; exit 2; }
fi
accepted='{}'
if [ -f "$ACCEPTED" ]; then
  accepted="$(jq -c '.' "$ACCEPTED")" || { echo "accepted.json is not valid JSON" >&2; exit 2; }
  jq -e 'type == "object" and all(.[]; type == "object")' >/dev/null 2>&1 <<<"$accepted" \
    || { echo "accepted.json must map control ids to objects" >&2; exit 2; }
fi

selected="$(jq -c --argjson ov "$overlays" '.[] | select(
    .layer == "baseline" or .layer == "gold"
    or ((.layer | startswith("overlay:")) and ((.layer | ltrimstr("overlay:")) as $n | $ov | index($n) != null)))' "$CONTROLS")" \
  || { echo "could not read controls: $CONTROLS" >&2; exit 2; }
expected=0
while IFS= read -r id; do
  [ -n "$id" ] || continue
  if [ -n "$ONLY" ]; then case " $ONLY " in *" $id "*) ;; *) continue ;; esac; fi
  expected=$((expected + 1))
done <<EOF
$(jq -r .id <<<"$selected")
EOF
prev="$FORTKEEP_REPORTS/latest/results.json"
if [ -n "$ONLY" ]; then
  for id in $ONLY; do
    jq -e --arg id "$id" 'select(.id == $id)' >/dev/null 2>&1 <<<"$selected" || { echo "unknown control: $id" >&2; exit 2; }
  done
  jq -e '.results | type == "array"' "$prev" >/dev/null 2>&1 \
    || { echo "run a full review first: checks/run.sh" >&2; exit 2; }
fi

mkdir -p "$FORTKEEP_REPORTS" || exit 1
run_id="$(date -u +%Y%m%dT%H%M%SZ)"
# One run per second: never reuse (or later delete) an earlier run's folder.
while [ -e "$FORTKEEP_REPORTS/$run_id" ]; do sleep 1; run_id="$(date -u +%Y%m%dT%H%M%SZ)"; done
out_dir="$FORTKEEP_REPORTS/$run_id"
mkdir "$out_dir" || exit 1
lines="$out_dir/.lines"
: > "$lines"

# A full run takes minutes and an agent's shell tool may give up on silence: one progress line per check, on stderr
# only, so stdout (the summary) and results.json stay the same. bin/fortkeep draws its progress line from these
# (checks/lib/ui.sh, ui_progress): keep their form.
n=0; start=$SECONDS
unset tools  # set below, never by the caller's environment
while IFS= read -r ctl; do
  [ -n "$ctl" ] || continue
  id="$(jq -r .id <<<"$ctl")"
  if [ -n "$ONLY" ]; then case " $ONLY " in *" $id "*) ;; *) continue ;; esac; fi
  check="$FORTKEEP_REPO/$(jq -r .check <<<"$ctl")"
  t="$(jq -r --arg d "$TIMEOUT" '.timeout // $d' <<<"$ctl")"
  case "$t" in ''|*[!0-9]*) ;; *) t=$((t * factor)) ;; esac
  n=$((n + 1)); printf 'fortkeep: %d/%d %s (%ds so far)\n' "$n" "$expected" "$id" "$((SECONDS - start))" >&2
  fortkeep_timeout "$t" /usr/bin/env -u BASH_ENV -u ENV /bin/bash -p "$check" > "$out_dir/.out" 2>/dev/null </dev/null
  rc=$?
  # Read once, and only when a check was killed: which security tools run here, for the ERROR to name.
  if [ -z "${tools+x}" ] && fortkeep_signal_name "$rc" >/dev/null; then
    tools="$(fortkeep_join "$(fortkeep_endpoint_running 2>/dev/null)" ', ')"
  fi
  res="$(fortkeep_check_verdict "$id" "$rc" "$(cat "$out_dir/.out")" "$t" "${tools:-}")"
  jq -c --argjson c "$ctl" --argjson acc "$accepted" '
    . + ($c | {id, title, layer, level, source})
    | if .status == "FAIL" and $acc[.id] != null then .status = "ACCEPTED" | .note = ($acc[.id].reason // "accepted") else . end
  ' <<<"$res" >> "$lines"
done <<EOF
$selected
EOF

if [ "$(grep -c . "$lines")" -ne "$expected" ]; then
  echo "run incomplete: some controls were not recorded" >&2; rm -rf "$out_dir"; exit 1
fi
os="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
if [ -n "$ONLY" ]; then
  # Recheck: previous full results with the rechecked rows replaced by id, so latest stays complete.
  build=(jq -s --slurpfile p "$prev" '. as $new | ($p[0].results) as $old
    | {run: $run, macos: $os, overlays: $ov, rechecked: ($new | map(.id)),
       results: ([$old[] | . as $r | (first($new[] | select(.id == $r.id)) // $r)]
                 + [$new[] | select(.id as $i | all($old[]; .id != $i))])}')
else
  build=(jq -s '{run: $run, macos: $os, overlays: $ov, results: .}')
fi
if ! "${build[@]}" --arg run "$run_id" --arg os "$os" --argjson ov "$overlays" "$lines" > "$out_dir/results.json"; then
  echo "failed to write results.json" >&2; rm -rf "$out_dir"; exit 1
fi
rm -f "$lines" "$out_dir/.out"
ln -sfn "$run_id" "$FORTKEEP_REPORTS/latest"
jq -r '.results | group_by(.status) | map("\(.[0].status): \(length)") | join("  ")' "$out_dir/results.json"
echo "report: reports/$run_id/results.json"
