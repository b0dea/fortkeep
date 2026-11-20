#!/bin/bash -p
# Accepts what is on this Mac now as your baseline: the latest KnockKnock scan (GD-RT-01), the programs listening on
# the network (GD-RT-02) and the hashes of the agent control files (GD-AI-01). Only you can: it refuses inside an
# agent or without a terminal, because the baseline text says the security check must never take one from an agent.
unset BASH_ENV ENV CDPATH
case "$0" in */*) here="${0%/*}" ;; *) here=. ;; esac  # no PATH lookup (dirname) before the agent check
# Only a copy that is exactly a signed release, checked before anything else is sourced.
. "$here/lib/repo.sh"
fortkeep_release_gate "$here/.." || exit 4
. "$here/lib/common.sh"
. "$here/lib/agent.sh"
[ "${1:-}" = accept ] || { echo "usage: $0 accept" >&2; exit 2; }

# /bin/ps is fixed here on purpose: no environment variable may switch the agent check off.
fortkeep_require_person /bin/ps
. "$here/lib/agents.sh"
. "$here/lib/baselines.sh"
K="$FORTKEEP_REPORTS/knockknock"; D="$(fortkeep_baseline_dir)"
fortkeep_baseline_safe || { echo "$(fortkeep_tilde "$D") or a file in it isn't a plain file in a plain folder: not accepting" >&2; exit 1; }
# Only you can read or replace them: the folder mode 700, each file mode 600 (mktemp's).
{ (umask 077 && mkdir -p "$D") && chmod 700 "$D"; } || { echo "could not make $D" >&2; exit 1; }
# Work from private copies: what is shown is exactly what is accepted, even if a weekly run replaces the scan meanwhile.
kt=""; lt=""; ct=""
trap 'rm -f "$kt" "$lt" "$ct"' EXIT
lt="$(mktemp "$D/.listeners.XXXXXX")" || { echo "could not make a temporary file" >&2; exit 1; }
ct="$(mktemp "$D/.control-files.XXXXXX")" || { echo "could not make a temporary file" >&2; exit 1; }
# Names come from the Mac being checked: strip control characters so none can hide or rewrite a line.
show() { LC_ALL=C /usr/bin/tr -d '\000-\010\013-\037\177' | sed '/^$/d; s/^/  /'; }

if [ -f "$K/latest.json" ]; then
  kt="$(mktemp "$D/.knockknock.XXXXXX")" || { echo "could not make a temporary file" >&2; exit 1; }
  cp "$K/latest.json" "$kt" || { echo "could not copy the scan" >&2; exit 1; }
  cur="$(fortkeep_knockknock_paths "$kt")" || { echo "the latest scan is not valid JSON" >&2; exit 1; }
  [ -n "$cur" ] || { echo "the latest scan lists no autostart items: not accepting it" >&2; exit 1; }
  base=""
  if [ -f "$D/knockknock.json" ]; then
    base="$(fortkeep_knockknock_paths "$D/knockknock.json")" || { echo "your current baseline is not valid JSON" >&2; exit 1; }
  fi
  new="$(fortkeep_baseline_new <(printf '%s\n' "$base") "$cur")"
  echo "Autostart items (KnockKnock): $(fortkeep_count "$new") item(s) would become part of your baseline:"
  printf '%s\n' "$new" | show
else
  echo "Autostart items (KnockKnock): no scan yet, skipped (the weekly security check runs one)"
fi

fortkeep_listeners > "$lt" || { echo "could not list the programs listening on the network" >&2; exit 1; }
lb=/dev/null; [ ! -f "$D/listeners.txt" ] || lb="$D/listeners.txt"
new="$(fortkeep_baseline_new "$lb" "$(cat "$lt")")"
echo "Programs listening on the network: $(fortkeep_count "$new") new:"
printf '%s\n' "$new" | show

fortkeep_control_files | fortkeep_control_hashes > "$ct"
base=""
[ ! -f "$D/control-files.txt" ] || base="$(cat "$D/control-files.txt")" || { echo "could not read your current baseline of control files" >&2; exit 1; }
new="$(fortkeep_control_diff "$base" "$(cat "$ct")" | while IFS=$'\t' read -r how p k; do printf '%s %s\n' "$how" "$(fortkeep_control_label "$p" "$k")"; done)"
echo "Agent control files: $(fortkeep_count "$new") changed, added or removed:"
printf '%s\n' "$new" | show
unread="$(awk -F'\t' '$3 == "unreadable" {print $1}' "$ct")"
[ -z "$unread" ] || { echo "Could not read (recorded as unreadable):"; printf '%s\n' "$unread" | show; }

printf 'Type accept to make all of this your baseline: '
read -r answer
[ "$answer" = accept ] || { echo "not accepted"; exit 1; }
{ [ -z "$kt" ] || mv "$kt" "$D/knockknock.json"; } && mv "$lt" "$D/listeners.txt" \
  && mv "$ct" "$D/control-files.txt" && echo "baseline accepted"
