#!/bin/bash
# Builds posture-summary.md and posture-summary.html next to results.json: ids, titles, levels and statuses, the
# person's written reason for each ACCEPTED item, and which devward and which controls produced them.
# Usage: summary/build.sh --name "Full Name" [results.json]
. "$(dirname "$0")/../checks/lib/common.sh"
. "$(dirname "$0")/../checks/lib/repo.sh"
usage() { echo "usage: $0 --name \"Full Name\" [results.json]" >&2; exit 2; }
fail() { echo "$1" >&2; rm -f "${tmp:-}" "${htmp:-}"; exit 1; }
name=""; res="$DEVWARD_REPORTS/latest/results.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --name) [ $# -ge 2 ] || usage; name="$2"; shift 2 ;;
    *) res="$1"; shift ;;
  esac
done
[ -n "$name" ] || usage
[ -f "$res" ] || { echo "no results yet: run checks/run.sh first" >&2; exit 2; }
jq -e '(.run | type == "string") and (.macos | type == "string") and (.overlays | type == "array") and (.results | type == "array")' "$res" >/dev/null 2>&1 \
  || { echo "results.json is not a valid devward report" >&2; exit 2; }
CONTROLS="${DEVWARD_CONTROLS:-$DEVWARD_REPO/controls/controls.json}"
want="$(jq -r --slurpfile r "$res" '($r[0].overlays | map("overlay:" + .)) as $ov
  | map(select(.layer == "baseline" or .layer == "gold" or (.layer as $l | $ov | index($l) != null)))
  | map(.id) | sort | join(" ")' "$CONTROLS" 2>/dev/null)" \
  || { echo "controls file missing or unreadable: $CONTROLS" >&2; exit 2; }
have="$(jq -r '.results | map(.id) | sort | join(" ")' "$res")"
[ "$have" = "$want" ] || { echo "results are incomplete: run /posture again" >&2; exit 2; }
dir="$(cd "$(dirname "$res")" && pwd -P)"
# The order checks/lib/results.jq sets: an urgent FAIL first, then MUST, SHOULD, NICE.
SORTED="$(jq -c -L "$DEVWARD_LIB_DIR" --slurpfile c "$CONTROLS" \
  'include "results"; ($c[0] | controls_by_id) as $ctl | .results | ordered($ctl)' "$res")" \
  || fail "could not order the results"
TABLE="$(jq -r '.[] | "| \(.id) | \(.title) | \(.level) | \(.status) |"' <<<"$SORTED")" || fail "could not read controls from results.json"
ACCEPTED="$(jq -r '
  [.results[] | select(.status == "ACCEPTED")] | sort_by(.id)
  | if length == 0 then "" else
      "## Accepted decisions\n\n| Control | Reason |\n|---|---|\n"
      + (map("| \(.id) | \((.note // "") | gsub("[\r\n]+"; " ") | gsub("\\|"; "/")) |") | join("\n")) + "\n"
    end' "$res")" || fail "could not read accepted reasons"
SUMMARY="$(jq -r -L "$DEVWARD_LIB_DIR" 'include "results"; .results | tally_text' "$res")" || fail "could not summarise results.json"
MACOS="$(jq -r '.macos | split(".")[0]' "$res")" || fail "could not read macOS version"
RUN="$(jq -r .run "$res")" || fail "could not read run id"
LAYERS="$(jq -r '(["baseline", "gold"] + (.overlays | map("overlay:" + .))) | join(", ")' "$res")" || fail "could not read overlays"
# Which devward wrote it: the release, only when this copy is exactly one with a signature this Mac trusts.
VERSION="unknown (git is not available)"; COMMIT="unknown"
if ! devward_needs_clt "$(command -v git || echo /usr/bin/git)" && devward_has git; then
  if COMMIT="$(devward_git "$DEVWARD_REPO" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)"; then
    if devward_verify_release "$DEVWARD_REPO"; then VERSION="$DEVWARD_RELEASE_TAG"
    else VERSION="not a signed release: $DEVWARD_RELEASE_PROBLEM"; fi
  else
    COMMIT="unknown"; VERSION="unknown (not a git checkout)"
  fi
fi
CTLHASH="$(shasum -a 256 "$CONTROLS" 2>/dev/null | cut -d' ' -f1)"
[ -n "$CTLHASH" ] || fail "could not hash the controls file: $CONTROLS"
# HTML fragments for templates/posture-summary.html: every value goes through esc, the page has no other input.
ESC='def esc: tostring | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;") | gsub("\""; "&quot;") | gsub([39] | implode; "&#39;");
  def pill: "<span class=\"pill \(.|ascii_downcase|esc)\">\(.|esc)</span>";'
H_ROWS="$(jq -r "$ESC"'
  .[]
  | (.id | esc) as $id
  | "<tr><td class=\"id\">\($id)</td><td>\(.title | esc)</td><td><span class=\"lvl\">\(.level | esc)</span></td><td>"
    + (if .status == "ACCEPTED" and ((.note // "") != "")
       then "<button type=\"button\" class=\"pill accepted tog\" aria-expanded=\"false\" aria-controls=\"r-\($id)\">ACCEPTED<span class=\"car\" aria-hidden=\"true\"></span></button></td></tr>"
            + "<tr class=\"why-row\" id=\"r-\($id)\" hidden><td></td><td colspan=\"3\"><span class=\"why-l\">Reason</span>\(.note | esc)</td></tr>"
       else "\(.status | pill)</td></tr>" end)' <<<"$SORTED")" || fail "could not build the HTML rows"
H_TALLY="$(jq -r -L "$DEVWARD_LIB_DIR" 'include "results"; '"$ESC"'.results | tally | map("\(.status | pill) <span>\(.count)</span>&nbsp;&nbsp;") | join("")' "$res")" || fail "could not build the HTML summary"
H_META="$(NAME="$name" RUN="$RUN" MACOS="$MACOS" LAYERS="$LAYERS" VERSION="$VERSION" COMMIT="$COMMIT" CTLHASH="$CTLHASH" jq -rn "$ESC"'
  [["Person", env.NAME], ["Checked (UTC)", env.RUN], ["macOS", env.MACOS], ["Standard", env.LAYERS],
   ["devward version", env.VERSION], ["devward commit", env.COMMIT], ["Controls (SHA-256)", env.CTLHASH]]
  | map("<div><dt>\(.[0] | esc)</dt><dd>\(.[1] | esc)</dd></div>") | join("")')" || fail "could not build the HTML details"
htmp="$(mktemp "$dir/.posture-summary.XXXXXX")" || fail "could not create temporary file"
META="$H_META" TALLY="$H_TALLY" ROWS="$H_ROWS" \
  perl -0pe 's/\{\{(META|TALLY|ROWS)\}\}/$ENV{$1}/g' "$DEVWARD_REPO/templates/posture-summary.html" > "$htmp" \
  || { rm -f "$htmp"; fail "could not render posture-summary.html"; }
tmp="$(mktemp "$dir/.posture-summary.XXXXXX")" || fail "could not create temporary file"
MDNAME="$(printf '%s' "$name" | tr '\r\n|' '  /')"  # one table cell
NAME="$MDNAME" RUN="$RUN" MACOS="$MACOS" LAYERS="$LAYERS" SUMMARY="$SUMMARY" TABLE="$TABLE" ACCEPTED="$ACCEPTED" \
  VERSION="$VERSION" COMMIT="$COMMIT" CTLHASH="$CTLHASH" \
  perl -0pe 's/\{\{(NAME|RUN|MACOS|LAYERS|SUMMARY|TABLE|ACCEPTED|VERSION|COMMIT|CTLHASH)\}\}/$ENV{$1}/g' "$DEVWARD_REPO/templates/posture-summary.md" > "$tmp" \
  || fail "could not render the posture summary"
mv -f "$tmp" "$dir/posture-summary.md" || fail "could not write posture-summary.md"
mv -f "$htmp" "$dir/posture-summary.html" || fail "could not write posture-summary.html"
echo "$dir/posture-summary.md"
