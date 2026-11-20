#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
. "$(dirname "$0")/../lib/baselines.sh"
ID=GD-RC-01
# The sweep reads every tracked file of every repo, so it runs in the weekly job only (and once, when there is no
# result yet); other runs report the stored result with its age.
# Kept beside the accepted baselines, where every agent guard refuses writes: a stored PASS mustn't be forgeable.
STORE="$HOME/.config/fortkeep/repo-sweep.json"
# Never read or write it through a symlink: a link could point the check at a PASS kept anywhere.
safe() { fortkeep_plain_store "${STORE%/*}" repo-sweep.json repo-sweep.json.tmp; }
if [ -z "${FORTKEEP_WEEKLY_RUN:-}" ] && { [ -e "$STORE" ] || [ -L "$STORE" ]; }; then
  safe || { fortkeep_result "$ID" ERROR "The stored result of the weekly repo sweep isn't a plain file in a plain folder" "$(fortkeep_tilde "$STORE") or its folder is a symlink or not a file: look at it, then delete it so the next review sweeps again"; exit 0; }
  r="$(jq -ce 'select((.status | IN("PASS", "FAIL", "NA", "ERROR")) and (.evidence | type == "string")
    and (.note | type == "string") and (.time | type == "number" and . == floor))' "$STORE" 2>/dev/null)" \
    || { fortkeep_result "$ID" ERROR "Could not read the stored result of the weekly repo sweep" "$(fortkeep_tilde "$STORE") is not a sweep result; the weekly security check (BL-AU-02) writes it again"; exit 0; }
  age=$(( $(date +%s) - $(jq -r '.time' <<<"$r") ))
  # A day of clock skew is allowed; a result dated later than that would never go stale.
  [ "$age" -ge -86400 ] || { fortkeep_result "$ID" ERROR "The stored result of the weekly repo sweep is dated in the future" "$(fortkeep_tilde "$STORE") is not a result this Mac's clock could have made; the weekly security check (BL-AU-02) writes it again"; exit 0; }
  days=$(( age > 0 ? age / 86400 : 0 ))
  [ "$days" -le 8 ] || { fortkeep_result "$ID" FAIL "The weekly sweep hasn't run: the last one is $days days old" "Check that the weekly security check runs (BL-AU-02)"; exit 0; }
  fortkeep_result "$ID" "$(jq -r '.status' <<<"$r")" "$(jq -r '.evidence' <<<"$r") (weekly sweep, $days day(s) ago)" "$(jq -r '.note' <<<"$r")"
  exit 0
fi
finish() {  # STATUS EVIDENCE [NOTE] — report the sweep's result and keep it for the runs until the next weekly one
  local out note="${3:-}"
  out="$(fortkeep_result "$ID" "$1" "$2" "$note")" || exit 1
  if ! { safe && (umask 077; mkdir -p "${STORE%/*}") && jq -c --argjson t "$(date +%s)" '{status, evidence, note, time: $t}' <<<"$out" > "$STORE.tmp" \
    && mv -f "$STORE.tmp" "$STORE"; } 2>/dev/null; then
    rm -f "$STORE.tmp" 2>/dev/null
    out="$(fortkeep_result "$ID" "$1" "$2" "${note:+$note }Could not store this result in $(fortkeep_tilde "$STORE"), so the next review sweeps again.")"
  fi
  printf '%s\n' "$out"
  exit 0
}
# The repo copy of the scanner, not the installed one: an edited ~/.local/bin copy can't hide a finding here.
SCAN="$FORTKEEP_REPO/fixes/files/git-scan-new-files"
t="${FORTKEEP_SWEEP_TIMEOUT:-140}"
budget=$(( t > 20 ? t - 15 : t / 2 ))  # the scanner stops itself first, so a slow sweep still reports what it found
skipped=""; looked=""; repos=(); blocked=""
# Desktop and Downloads too: cloned or unzipped repos often land there.
for d in dev Developer code src Projects work git repos workspace Development source Documents/GitHub Desktop Downloads; do
  d="$HOME/$d"
  [ -d "$d" ] || continue
  if fortkeep_is_private "$d"; then skipped=" (a private folder was excluded)"; continue; fi
  # Desktop, Downloads and Documents need macOS privacy permission: a folder it hides would look empty.
  ls "$d" >/dev/null 2>&1 || { blocked="$blocked $(fortkeep_tilde "$d")"; continue; }
  looked="$looked $(fortkeep_tilde "$d")"
  while IFS= read -r p; do case "$p" in "$d"/*) [ ! -e "$p" ] || skipped=" (a private folder was excluded)" ;; esac; done <<EOF
$(fortkeep_private_list)
EOF
  # A repo is a folder with .git in it (a folder, or a file for worktrees and submodules), at most 4 levels down.
  # Hidden folders (caches, .claude, .worktrees) and node_modules hold copies, not repos of yours.
  # NUL-separated, as a folder name can hold a newline; a repo folder that can't be opened is reported, not skipped.
  while IFS= read -r -d '' g; do
    if r="$(cd "${g%/.git}" 2>/dev/null && pwd -P && echo .)"; then r="${r%.}"; repos+=("${r%$'\n'}")
    else blocked="$blocked $(fortkeep_tilde "${g%/.git}")"; fi
  done < <(fortkeep_walk "$d" -maxdepth 5 \( -name node_modules -o \( -name '.*' ! -name .git \) \) -prune -o -name .git -prune -print0)
done
blk=""; [ -z "$blocked" ] || blk=" macOS privacy settings blocked reading:$blocked."
none() {  # the result when there is no repo to sweep
  [ -z "$blocked" ] || finish ERROR "Could not read every code folder" "${blk# }$skipped"
  finish NA "No git repos found in your code folders" "Looked in:${looked:- none of ~/dev, ~/Developer, ~/code, ~/src, ~/Projects, ~/work, ~/git, ~/repos, ~/workspace, ~/Development, ~/source, ~/Documents/GitHub, ~/Desktop or ~/Downloads exist}$skipped"
}
# Beyond repos: the editors' extension folders, where a trojanized extension carries the same loader markers.
trees=()
for e in "$HOME"/.vscode*/extensions "$HOME"/.cursor*/extensions "$HOME"/.windsurf*/extensions; do
  [ -d "$e" ] || continue
  if fortkeep_is_private "$e" || fortkeep_private_physical "$(fortkeep_realpath "$e")"; then skipped=" (a private folder was excluded)"; else trees+=(--tree "$e"); fi
done
nx=$(( ${#trees[@]} / 2 ))
# And npm's own lib/cli.js, which the loader appends itself to: each install a version manager keeps, and each npm
# on the person's PATH, found as `npm root -g` would find it, without running npm. Safe Chain's shims aren't npm.
clis=""
for c in "$(fortkeep_path /opt/homebrew/lib/node_modules/npm/lib/cli.js)" "$(fortkeep_path /usr/local/lib/node_modules/npm/lib/cli.js)" \
  "$HOME"/.nvm/versions/node/*/lib/node_modules/npm/lib/cli.js "$HOME"/.volta/tools/image/node/*/lib/node_modules/npm/lib/cli.js \
  "$HOME"/.volta/tools/image/npm/*/lib/cli.js "$HOME"/.asdf/installs/nodejs/*/lib/node_modules/npm/lib/cli.js \
  "$HOME"/.local/share/mise/installs/node/*/lib/node_modules/npm/lib/cli.js "$(fortkeep_path /usr/local/n/versions/node)"/*/lib/node_modules/npm/lib/cli.js \
  "$HOME"/.local/share/fnm/node-versions/*/installation/lib/node_modules/npm/lib/cli.js "$HOME"/.fnm/node-versions/*/installation/lib/node_modules/npm/lib/cli.js \
  "$HOME/Library/Application Support/fnm/node-versions/"*/installation/lib/node_modules/npm/lib/cli.js; do
  [ -f "$c" ] && clis="$clis$(fortkeep_realpath "$c")"$'\n'
done
IFS=: read -r -a pdirs <<<"$FORTKEEP_USER_PATH"
for p in ${pdirs[@]+"${pdirs[@]}"}; do
  case "$p" in ''|"$HOME"/.safe-chain*) continue ;; esac
  [ -e "$p/npm" ] || continue
  r="$(fortkeep_realpath "$p/npm")"; c="${r%/*/*}/lib/cli.js"
  [ -n "$r" ] && [ -f "$c" ] && clis="$clis$(fortkeep_realpath "$c")"$'\n'
done
npms=()
while IFS= read -r c; do
  [ -n "$c" ] || continue
  if fortkeep_private_physical "$c"; then skipped=" (a private folder was excluded)"; else npms+=(--npm-cli "$c"); fi
done <<EOF
$(printf '%s' "$clis" | awk '!s[$0]++')
EOF
nn=$(( ${#npms[@]} / 2 ))
[ ${#repos[@]} -gt 0 ] || [ $((nx + nn)) -gt 0 ] || none
# Repos are physical paths: one that is private under another spelling is never opened. Inside the rest, the
# scanner leaves out every file under a private folder, by either spelling of it.
args=(); priv=()
while IFS= read -r -d '' r; do
  [ -n "$r" ] || continue
  if fortkeep_private_physical "$r"; then skipped=" (a private folder was excluded)"; else args+=("$r"); fi
done < <(printf '%s\0' ${repos[@]+"${repos[@]}"} | sort -zu)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  priv+=(--private "$p"); r="$(cd "$p" 2>/dev/null && pwd -P)" && [ "$r" != "$p" ] && priv+=(--private "$r")
done <<EOF
$(fortkeep_private_list)
EOF
[ ${#args[@]} -gt 0 ] || [ $((nx + nn)) -gt 0 ] || none
# Without Command Line Tools, /usr/bin/python3 opens an install dialog. Not stored: the next run checks again.
if ! xcode-select -p >/dev/null 2>&1 || [ ! -x /usr/bin/python3 ]; then
  fortkeep_result "$ID" ERROR "The repo sweep needs Apple's Command Line Tools, which aren't installed" "Run xcode-select --install in the Terminal app, then run the check again$skipped"
  exit 0
fi
# npm first (quick), the extension folders last (slow): a sweep cut short still covers the repos.
out="$(fortkeep_timeout "$t" /usr/bin/python3 -I "$SCAN" --sweep --budget "$budget" ${priv[@]+"${priv[@]}"} ${npms[@]+"${npms[@]}"} \
  ${args[@]+"${args[@]}"} ${trees[@]+"${trees[@]}"} 2>/dev/null)"; rc=$?
[ "$rc" -ne 142 ] || finish ERROR "The repo sweep timed out after ${t}s" "Run the check again when the Mac is less busy$skipped"
done_line="$(printf '%s\n' "$out" | grep '^DONE	' | tail -n 1)"
{ [ "$rc" -eq 0 ] && [ -n "$done_line" ]; } || finish ERROR "The repo scanner failed (exit $rc)" "fixes/files/git-scan-new-files --sweep gave no summary$skipped"
printf '%s\n' "$out" | grep -q '^PRIVATE	' && skipped=" (a private folder was excluded)"
swept="$(printf '%s' "$done_line" | cut -f2)"; total="$(printf '%s' "$done_line" | cut -f3)"
show() {  # SEVERITY — up to three findings as repo:file (what)
  fortkeep_join "$(printf '%s\n' "$out" | awk -F'\t' -v s="$1" '$1 == s' | head -3 | while IFS=$'\t' read -r _ repo file what; do
    printf '%s:%s (%s)\n' "$(fortkeep_tilde "$repo")" "$file" "$what"
  done)" '; '
}
count() { fortkeep_count "$(printf '%s\n' "$out" | awk -F'\t' -v s="$1" '$1 == s')"; }
repos_of() { fortkeep_join "$(printf '%s\n' "$out" | awk -F'\t' -v s="$1" '$1 == s {print $2}' | head -3 | while IFS= read -r r; do fortkeep_tilde "$r"; done)" ', '; }
nh="$(count HIGH)"; nw="$(count WARN)"; nu="$(count UNREAD)"; np="$(count INFO)"; ne="$(count ERROR)"
lower=""; [ "$nw" -eq 0 ] || lower=" $nw lower-confidence finding(s) to look at: $(show WARN)."
unread=""; [ "$nu" -eq 0 ] || unread=" Could not list the files of $nu repo(s): $(repos_of UNREAD)."
[ "$ne" -eq 0 ] || unread="$unread Could not read $ne part(s) of the repos: $(show ERROR)."
part=""; [ "$np" -eq 0 ] || part=" $np repo(s) over 5000 files had only their config, hook and agent files scanned: $(repos_of INFO)."
what="repo(s)"; [ "$nx" -eq 0 ] || what="repo(s) and extension folder(s)"
partly=""; [ $((swept + nu)) -ge "$total" ] || partly=" The time ran out after $swept of $total ${what//(s)/s}."
if [ "$nh" -gt 0 ]; then
  nr="$(fortkeep_count "$(printf '%s\n' "$out" | awk -F'\t' '$1 == "HIGH" {print $2}' | sort -u)")"
  where="repo(s)"; printf '%s\n' "$out" | awk -F'\t' '$1 == "HIGH" {print $2}' | grep -q '/extensions$' && where="repo(s) or extension folder(s)"
  printf '%s\n' "$out" | awk -F'\t' '$1 == "HIGH" {print $2}' | grep -q '/lib/cli\.js$' && where="$where or npm install(s)"
  finish FAIL "$nh repo-poisoning indicator(s) in $nr $where" \
    "$(show HIGH). Don't install, build, run or open these in an agent or editor; type /if-red.$partly$unread$blk$part$lower$skipped"
elif [ -n "$partly" ] || [ "$nu" -gt 0 ] || [ "$ne" -gt 0 ] || [ -n "$blocked" ]; then
  note="${partly# }$unread$blk$part$lower$skipped"
  finish ERROR "Swept $swept of $total $what, none flagged so far" "${note# }"
else
  note="${part# }$lower$skipped"
  ext=""; [ "$nx" -eq 0 ] || ext=" and $nx editor extension folder(s)"
  [ "$nn" -eq 0 ] || ext="$ext and $nn npm install(s)"
  finish PASS "${#args[@]} repo(s)$ext swept, none flagged" "${note# }"
fi
