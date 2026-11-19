#!/bin/bash
# Runs the bats test files side by side and prints each file's output whole, in name order, then one summary
# line. A file is the unit: tests inside one file still run in order, so a file's own setup stays valid.
# Usage: ci/run-tests.sh [FILE_OR_FOLDER]...   (default: tests)
# Env:   JOBS, how many files run at once (default 4, never more than this Mac's cores; 1 runs bats directly).
# Exit:  0 when every file passed, 1 otherwise.
[ $# -gt 0 ] || set -- tests
files=()
for a in "$@"; do
  if [ -d "$a" ]; then for f in "$a"/*.bats; do [ -f "$f" ] && files+=("$f"); done
  else files+=("$a"); fi
done
[ ${#files[@]} -gt 0 ] || { echo "run-tests: no test files in: $*" >&2; exit 1; }
cores="$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
jobs="${JOBS:-4}"
case "$jobs" in ''|*[!0-9]*|0) echo "run-tests: JOBS must be a number above 0" >&2; exit 1 ;; esac
[ "$jobs" -le "$cores" ] || jobs="$cores"
# One file, or one job: bats itself, with its usual live output.
if [ ${#files[@]} -eq 1 ] || [ "$jobs" -eq 1 ]; then exec bats "${files[@]}"; fi

out="$(mktemp -d)" || exit 1
trap 'rm -rf "$out"' EXIT
# The longest files start first, so the last worker isn't left alone with the biggest one.
count() { local c; c="$(grep -c "$1" "$2" 2>/dev/null)"; printf '%s\n' "${c:-0}"; }  # PATTERN FILE: matching lines, 0 if unreadable
order="$(for f in "${files[@]}"; do printf '%s\t%s\n' "$(count '^@test' "$f")" "$f"; done | sort -rn | cut -f2-)"
# OUT is exported: the worker shell reads it from the environment, so no path is pasted into its script.
export OUT="$out"
# shellcheck disable=SC2016  # the worker's own variables, expanded by the shell xargs starts
printf '%s\n' "$order" | tr '\n' '\0' | xargs -0 -n 1 -P "$jobs" /bin/sh -c '
  f="$1"; n="$(printf "%s" "$f" | tr "/" "_")"; start="$(date +%s)"
  bats "$f" > "$OUT/$n.tap" 2>&1; rc=$?
  printf "%s\n" "$rc" > "$OUT/$n.rc"
  if [ "$rc" -eq 0 ]; then word=ok; else word=FAILED; fi
  printf "%s %s (%ss)\n" "$word" "$f" "$(( $(date +%s) - start ))" >&2
' run-tests
ok=0; bad=0; failed=""
while IFS= read -r f; do
  n="$(printf '%s' "$f" | tr '/' '_')"
  printf '# %s\n' "$f"
  cat "$out/$n.tap" 2>/dev/null
  ok=$((ok + $(count '^ok ' "$out/$n.tap")))
  bad=$((bad + $(count '^not ok ' "$out/$n.tap")))
  # A file whose bats never ran, or crashed without a "not ok" line, is a failure too.
  [ "$(cat "$out/$n.rc" 2>/dev/null)" = 0 ] || failed="$failed $f"
done <<EOF
$(printf '%s\n' "${files[@]}" | sort)
EOF
echo "tests: $ok ok, $bad not ok, in ${#files[@]} files, $jobs at a time"
[ -z "$failed" ] || { echo "failed:$failed" >&2; exit 1; }
