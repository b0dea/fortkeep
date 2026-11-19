#!/bin/bash -p
# Scans one folder the person names for signs of a poisoned repo, before they open, install, build or run it: the
# folder's own repo and every git repo under it (at most four levels down, not in hidden folders or node_modules).
# Read-only: the repo scanner's sweep (fixes/files/git-scan-new-files --sweep, as GD-RC-01 runs it) reads each repo's
# files, tracked or not (a download's payload needn't be committed; node_modules aside), its git hooks and history.
# Nothing from a repo runs, and a repo whose git data lives outside the folder (a worktree or submodule of a repo
# elsewhere) is left out. Private folders are left out and never named, in any letter case.
# Usage: checks/scan.sh FOLDER   (absolute, or starting with ~/)
# Prints one line per finding (HIGH, WARN, ERROR or NOTE, then the repo, the file and what was found), one per repo
# left out (SKIP), then the verdict line.
# Exit: 0 clean: every repo scanned, nothing flagged
#       1 HIGH: signs of a poisoned repo; don't open, install, build or run it
#       2 refused: not one existing folder, or /, the home folder, a folder above it, devward's own folder, or a .git folder
#       3 look: only lower-confidence findings (WARN)
#       4 incomplete: a repo not scanned in full (time, unreadable, too large, git data elsewhere), no repo found, or the
#         folder is private
# A HIGH is reported (exit 1) even when the scan was cut short: the scanner prints each one as soon as it finds it.
# Started as `bash scan.sh`: start again in privileged mode, which ignores BASH_ENV, ENV and exported functions.
case $- in *p*) ;; *) exec /usr/bin/env -u BASH_ENV -u ENV /bin/bash -p "$0" "$@" ;; esac
case "$0" in */*) . "${0%/*}/lib/common.sh" ;; *) . ./lib/common.sh ;; esac
devward_clean_start "$0" "$@"
. "$DEVWARD_LIB_DIR/agents.sh"  # devward_private_physical

refuse() { echo "$1" >&2; exit 2; }
[ $# -eq 1 ] && [ -n "$1" ] || refuse "usage: $0 FOLDER   (absolute, or starting with ~/)"
dir="$(devward_private_folder "$1")" || refuse "use an absolute path, or one starting with ~/, without . or .. in it"
excluded="Verdict: not scanned. A private folder was excluded."
if devward_is_private "$dir"; then echo "$excluded"; exit 4; fi
[ -d "$dir" ] || refuse "no such folder: $dir"
phys="$(cd "$dir" 2>/dev/null && pwd -P)" || refuse "could not open the folder: $dir"
if devward_private_physical "$phys"; then echo "$excluded"; exit 4; fi
devward_private_refused "$dir" \
  && refuse "that is /, your home folder, a folder above it, or devward's own folder: name one project folder"
# A repo's .git folder, as named or where a link leads: the repo is the folder above it, outside what was named.
for n in "${dir##*/}" "${phys##*/}"; do
  [ "$(printf '%s' "$n" | devward_fold)" != .git ] || refuse "that is a repo's .git folder: name the repo's own folder"
done

inside() { case "$1" in "$phys"/*|"$phys") return 0 ;; esac; return 1; }
show() {  # PHYSICAL_PATH — as the person spelled the folder, ~/ for the home folder
  local p="$1"; case "$p" in "$phys"/*|"$phys") p="$dir${p#"$phys"}" ;; esac; devward_tilde "$p"
}
gitdir_inside() {  # REPO — true when the git folder git reads for REPO (a worktree's shared one too) is inside the folder
  local d="$1/.git" c
  # Their first line only, from at most 4 KB: a huge or sparse file can't stall the read.
  if [ -f "$d" ] && [ ! -L "$d" ]; then
    d="$(head -c 4096 "$d" | sed -n '1s/^gitdir: //p;q')"; case "$d" in /*) ;; *) d="$1/$d" ;; esac
  fi
  d="$(cd "$d" 2>/dev/null && pwd -P)" && inside "$d" || return 1
  [ -f "$d/commondir" ] || return 0
  c="$(head -c 4096 "$d/commondir" | sed -n '1p;q')"; case "$c" in /*) ;; *) c="$d/$c" ;; esac
  c="$(cd "$c" 2>/dev/null && pwd -P)" && inside "$c"
}

skipped=""; repos=(); skips=""
# A folder name may hold control characters: shown as ?, so it can't rewrite the terminal or add a line.
printable() { printf '%s' "$1" | LC_ALL=C perl -pe 's/[\x00-\x1f\x7f]|\xc2[\x80-\x9f]/?/g'; }
# A repo is a folder with .git in it, found as GD-RC-01 finds them: hidden folders and node_modules below the folder
# hold copies, not repos. The folder itself may be hidden, and is never matched (-mindepth 1): its own .git is below it.
while IFS= read -r -d '' g; do
  r="${g%/.git}"
  if devward_private_physical "$r"; then skipped=1
  elif ! gitdir_inside "$r"; then skips="$skips$(printable "$(show "$r")")"$'\n'
  else repos+=("$r"); fi
done < <(devward_walk "$phys" -mindepth 1 -maxdepth 5 \( -name node_modules -o \( -name '.*' ! -name .git \) \) -prune \
  -o -name .git -prune -print0)
fphys="$(printf '%s' "$phys" | devward_fold)"; fdir="$(printf '%s' "$dir" | devward_fold)"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$(printf '%s' "$p" | devward_fold)" in "$fphys"/*|"$fdir"/*) [ ! -e "$p" ] || skipped=1 ;; esac
done <<EOF
$(devward_private_list)
EOF
priv=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  priv+=(--private "$p"); r="$(cd "$p" 2>/dev/null && pwd -P)" && [ "$r" != "$p" ] && priv+=(--private "$r")
done <<EOF
$(devward_private_list)
EOF
excl=""; [ -z "$skipped" ] || excl=" A private folder was excluded."
nskip="$(devward_count "$skips")"
skip_lines() { printf '%s' "$skips" | while IFS= read -r r; do printf 'SKIP  %s  its git data is outside this folder, so it was not scanned\n' "$r"; done; }
if [ ${#repos[@]} -eq 0 ]; then
  [ "$nskip" -gt 0 ] && { skip_lines; echo "Verdict: incomplete. Scanned 0 of $nskip repo(s).$excl"; exit 4; }
  echo "Verdict: incomplete. No git repo in that folder: this scan reads git repos only. Name the folder that holds .git.$excl"
  exit 4
fi
# Without Command Line Tools, /usr/bin/python3 opens an install dialog.
if ! xcode-select -p >/dev/null 2>&1 || [ ! -x /usr/bin/python3 ]; then
  echo "Verdict: incomplete. The scan needs Apple's Command Line Tools: type xcode-select --install in the Terminal app, then scan again."
  exit 4
fi
# The repo copy of the scanner, not the installed hook, with GD-RC-01's time limits: it stops itself first. Untracked
# and ignored files too: a downloaded folder's payload needn't be committed.
SCAN="$DEVWARD_REPO/fixes/files/git-scan-new-files"
t="${DEVWARD_SWEEP_TIMEOUT:-140}"
budget=$(( t > 20 ? t - 15 : t / 2 ))
out="$(devward_timeout "$t" /usr/bin/python3 -I "$SCAN" --sweep --budget "$budget" ${priv[@]+"${priv[@]}"} --untracked "${repos[@]}" 2>/dev/null)"; rc=$?
total=$(( ${#repos[@]} + nskip ))
# What the scanner printed before it stopped counts, whatever stopped it: a HIGH is never lost to the time.
done_line="$(printf '%s\n' "$out" | grep '^DONE	' | tail -n 1)"
printf '%s\n' "$out" | grep -q '^PRIVATE	' && excl=" A private folder was excluded."
swept="$(printf '%s' "$done_line" | cut -f2)"; swept="${swept:-0}"
# Most serious first. The scanner's fields hold no control character (its field()), so a file name can't rewrite
# the terminal. Tabs become \037, which isn't blank to read, so an empty field stays a field.
for s in HIGH WARN ERROR UNREAD INFO; do
  printf '%s\n' "$out" | tr '\t' '\037' | while IFS=$'\037' read -r sev r f what; do
    [ "$sev" = "$s" ] || continue
    case "$sev" in UNREAD) sev=ERROR ;; INFO) sev=NOTE ;; esac
    printf '%-5s %s  %s  %s\n' "$sev" "$(show "$r")" "${f:-(repo)}" "$what"
  done
done
skip_lines
count() { devward_count "$(printf '%s\n' "$out" | awk -F'\t' -v s="$1" '$1 == s')"; }
nh="$(count HIGH)"; nw="$(count WARN)"; nu="$(count UNREAD)"; ne="$(count ERROR)"; ni="$(count INFO)"
failed=""; [ "$rc" -eq 0 ] && [ -n "$done_line" ] || failed=1
if [ "$nh" -gt 0 ]; then
  nr="$(devward_count "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "HIGH" {print $2}' | sort -u)")"
  late=""
  if [ "$rc" -eq 142 ] || [ $((swept + nu)) -lt ${#repos[@]} ]; then late=" The time ran out before every repo was scanned."
  elif [ -n "$failed" ]; then late=" The repo scanner failed (exit $rc) part way."; fi
  echo "Verdict: HIGH. $nh sign(s) of a poisoned repo in $nr of $total repo(s). Don't install, build, run or open it in an agent or editor; type /if-red.$late$excl"
  exit 1
fi
[ "$rc" -ne 142 ] || { echo "Verdict: incomplete. The scan timed out after ${t}s; scan again when the Mac is less busy.$excl"; exit 4; }
[ -z "$failed" ] || { echo "Verdict: incomplete. The repo scanner failed (exit $rc).$excl"; exit 4; }
if [ $((swept + nu)) -lt ${#repos[@]} ] || [ $((nu + ne + nskip + ni)) -gt 0 ]; then
  why=""
  [ $((swept + nu)) -ge ${#repos[@]} ] || why=" The time ran out."
  [ $((nu + ne)) -eq 0 ] || why="$why Some of it couldn't be read (the ERROR lines)."
  [ "$ni" -eq 0 ] || why="$why Some repos were too large to read in full (the NOTE lines)."
  [ "$nskip" -eq 0 ] || why="$why Some repos were left out (the SKIP lines)."
  echo "Verdict: incomplete. Scanned $swept of $total repo(s), nothing flagged so far.$why$excl"
  exit 4
fi
if [ "$nw" -gt 0 ]; then
  echo "Verdict: look. Nothing that marks a poisoned repo, but $nw lower-confidence finding(s) to look at.$excl"
  exit 3
fi
echo "Verdict: clean. $swept repo(s) scanned, nothing flagged.$excl"
exit 0
