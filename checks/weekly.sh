#!/bin/bash -p
# Weekly security check, run by the io.github.b0dea.fortkeep.weekly LaunchAgent: a KnockKnock scan when installed,
# a full review with a notification naming anything that newly fails, then a Homebrew report. Like run.sh,
# it writes its reports (and reports/weekly-last, which dates the last review) from inside checks/.
case $- in *p*) ;; *) exec /usr/bin/env -u BASH_ENV -u ENV /bin/bash -p "$0" "$@" ;; esac
case "$0" in */*) here="${0%/*}" ;; *) here=. ;; esac
. "$here/lib/common.sh"
fortkeep_clean_start "$0" "$@"
. "$here/lib/apps.sh"
. "$here/lib/shells.sh"
. "$here/lib/repo.sh"
BREW_TIMEOUT="${FORTKEEP_BREW_TIMEOUT:-600}"
CONTROLS="${FORTKEEP_CONTROLS:-$FORTKEEP_REPO/controls/controls.json}"
open_it="open the Terminal app, type cd $(fortkeep_tilde "$FORTKEEP_REPO"), start your coding agent there and type /posture (in Codex, \$posture)."
notify() {  # MESSAGE [TITLE] — a Notification Center banner; quotes and backslashes are escaped for AppleScript
  local m t
  [ -z "${FORTKEEP_NO_NOTIFY:-}" ] || return 0
  m="$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')"; t="$(printf '%s' "${2:-fortkeep}" | sed 's/[\\"]/\\&/g')"
  osascript -e "display notification \"$m\" with title \"$t\"" >/dev/null 2>&1
}
fails() { jq -r '[.results[]? | select(.status == "FAIL") | .id] | sort | .[]' "$FORTKEEP_REPORTS/latest/results.json" 2>/dev/null; }
titles() {  # urgent|other IDS — the titles of these failing controls that are urgent (checks/lib/results.jq), or the
  # others, joined with commas
  jq -r -L "$FORTKEEP_LIB_DIR" --arg kind "$1" --arg ids "$2" --slurpfile c "$CONTROLS" '
    include "results"; ($c[0] | controls_by_id) as $ctl | ($ids | split("\n")) as $new
    | [.results[] | select(.id as $i | $new | index($i)) | select(urgent($ctl) == ($kind == "urgent")) | .title]
    | join(", ")' "$FORTKEEP_REPORTS/latest/results.json"
}
brew_report() {  # brew update, then the formulae with a released fix for a known vulnerability; never upgrades
  local start left out rc n
  fortkeep_has brew || { echo "Homebrew step skipped: brew not found"; return 0; }
  start=$SECONDS
  echo "Homebrew: brew update"
  fortkeep_timeout "$BREW_TIMEOUT" brew update 2>&1; rc=$?
  [ "$rc" -eq 0 ] || echo "brew update failed or timed out (exit $rc)"
  left=$((BREW_TIMEOUT - (SECONDS - start)))
  [ "$left" -gt 0 ] || { echo "brew vulns skipped: the Homebrew step ran out of time"; return 0; }
  echo "Homebrew: brew vulns --fix-available --json"
  out="$(fortkeep_timeout "$left" env HOMEBREW_NO_AUTO_UPDATE=1 brew vulns --fix-available --json 2>/dev/null)"; rc=$?
  printf '%s\n' "$out"
  [ "$rc" -ne 142 ] || { echo "brew vulns timed out"; return 0; }
  # brew vulns exits 1 when it lists findings, so the JSON decides, not the exit code.
  n="$(jq -er '.findings | if type == "array" then length else error("no findings list") end' <<<"$out" 2>/dev/null)" \
    || { echo "brew vulns failed or gave no JSON (exit $rc)"; return 0; }
  echo "Homebrew: $n formula(e) with a vulnerability that has a released fix"
  if [ "$n" -eq 1 ]; then notify "Homebrew: 1 formula has a vulnerability with a released fix. Run brew upgrade in the Terminal app."
  elif [ "$n" -gt 1 ]; then notify "Homebrew: $n formulae have a vulnerability with a released fix. Run brew upgrade in the Terminal app."; fi
  return 0
}
echo "weekly check $(date -u +%FT%TZ)"
# Anything running as this user can edit the scripts this job runs, and the warning at the agent's session start
# doesn't cover a job that runs on its own. Like a fix, it runs only from a copy that is exactly a signed release;
# otherwise it refuses and leaves weekly-last alone, so BL-AU-02 goes overdue.
refuse() {
  echo "Refused to run the review: $1"
  notify "The weekly security review did not run: this copy of fortkeep is not exactly a signed release. If you didn't change it, reinstall fortkeep. Details: ~/Library/Logs/fortkeep-weekly.log"
  exit 1
}
gate="$(fortkeep_release_gate "$FORTKEEP_REPO" 2>&1)" || refuse "${gate#REFUSED: }"
[ -z "$gate" ] || echo "$gate"  # a downgrade warning
# launchd's PATH is bare: the review inspects the person's login-shell PATH, or launchd's if that shell can't be
# read. It only adds tools (brew): the commands this script runs still come from the system folders first.
lp="$FORTKEEP_USER_PATH"
out="$(fortkeep_shell_probe zsh-login 'printf "%s\n" "$PATH"; echo fortkeep-done')" && l="$(printf '%s\n' "$out" | awk '{p=l; l=$0} END{if (l == "fortkeep-done") print p}')"
case "$l" in /*) lp="$l"; PATH="$PATH:$l" ;; esac
before="$(fails)"
if app="$(fortkeep_app KnockKnock)"; then
  mkdir -p "$FORTKEEP_REPORTS/knockknock"
  tmp="$FORTKEEP_REPORTS/knockknock/scan.json.tmp"
  if fortkeep_timeout 900 open -n -W -a "$app" --stdout "$tmp" --args -whosthere -skipVT && jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$FORTKEEP_REPORTS/knockknock/latest.json"
  else
    rm -f "$tmp"; echo "KnockKnock scan failed or gave no JSON"
  fi
fi
if ! /usr/bin/env PATH="$lp" "$FORTKEEP_REPO/checks/run.sh" --weekly; then notify "The weekly security review could not finish. The reason is in ~/Library/Logs/fortkeep-weekly.log. To run it yourself, $open_it"; exit 1; fi
touch "$FORTKEEP_REPORTS/weekly-last" || { echo "could not record the review date" >&2; exit 1; }
new="$(comm -13 <(printf '%s\n' "$before" | sed '/^$/d') <(fails))"
if [ -n "$new" ]; then
  if urgent="$(titles urgent "$new")" && other="$(titles other "$new")"; then
    [ -z "$urgent" ] || notify "Signs of possible malware: $urgent. Turn off Wi-Fi now and don't type passwords. Then read $(fortkeep_tilde "$FORTKEEP_REPO")/docs/if-red.md for what to do next." "fortkeep: possible malware on this Mac"
    [ -z "$other" ] || notify "Newly failing: $other. To see why and fix it, $open_it"
  else
    echo "could not read the titles of the newly failing controls from $CONTROLS"
    notify "Newly failing: $(printf '%s\n' "$new" | paste -sd, - | sed 's/,/, /g'). To see why and fix it, $open_it"
  fi
fi
brew_report
echo "done"
