#!/bin/bash
# Saves run settings. Full setup: checks/configure.sh --overlays "a,b" --teach yes|no (every overlay counts as
# offered). Later: checks/configure.sh --offered "a,b" --add-overlays "x" records overlays offered since then.
. "$(dirname "$0")/lib/common.sh"
CONTROLS="${DEVWARD_CONTROLS:-$DEVWARD_REPO/controls/controls.json}"
CONFIG="${DEVWARD_CONFIG:-$DEVWARD_REPORTS/config.json}"
usage() { echo "usage: $0 --overlays \"a,b\" --teach yes|no   or   $0 --offered \"a,b\" --add-overlays \"x\"" >&2; exit 2; }
overlays=""; teach=""; offered=""; add=""; full=0; merge=0
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || usage
  case "$1" in
    --overlays) overlays="$2"; full=1 ;;
    --teach) teach="$2"; full=1 ;;
    --offered) offered="$2"; merge=1 ;;
    --add-overlays) add="$2"; merge=1 ;;
    *) usage ;;
  esac
  shift 2
done
[ $((full + merge)) -eq 1 ] || usage
known="$(jq -c '[.[].layer | select(startswith("overlay:")) | ltrimstr("overlay:")] | unique' "$CONTROLS")" \
  || { echo "could not read controls: $CONTROLS" >&2; exit 2; }
names() { jq -cn --arg s "$1" '$s | split(",") | map(gsub("^ +| +$"; "")) | map(select(length > 0))'; }
known_only() {  # JSON_LIST — exit 2 naming any overlay controls.json doesn't have
  local u; u="$(jq -rn --argjson ov "$1" --argjson k "$known" '$ov - $k | join(", ")')"
  [ -z "$u" ] || { echo "unknown overlay(s): $u (known: $(jq -r 'join(", ")' <<<"$known"))" >&2; exit 2; }
}
mkdir -p "$(dirname "$CONFIG")"
if [ "$full" -eq 1 ]; then
  case "$teach" in yes|no) ;; *) echo "--teach must be yes or no" >&2; exit 2 ;; esac
  ov="$(names "$overlays")"; known_only "$ov"
  jq -n --argjson ov "$ov" --argjson off "$known" --arg teach "$teach" --arg at "$(date -u +%FT%TZ)" \
    '{overlays: $ov, offered: $off, teach: ($teach == "yes"), configured: $at}' > "$CONFIG"
  echo "saved: overlays=$(jq -r 'join(",")' <<<"$ov") teach=$teach"
  exit 0
fi
[ -f "$CONFIG" ] || { echo "no settings yet: run the full setup first" >&2; exit 2; }
off="$(names "$offered")"; ad="$(names "$add")"; known_only "$off"; known_only "$ad"
jq -e 'type == "object" and ((.overlays // []) | type == "array")' "$CONFIG" >/dev/null 2>&1 \
  || { echo "config.json is not valid JSON" >&2; exit 2; }
# A config from before `offered` existed counts its chosen overlays as offered.
tmp="$(mktemp "$CONFIG.XXXXXX")" || exit 1
if jq --argjson off "$off" --argjson ad "$ad" '(.offered // .overlays // []) as $was
    | .overlays = (((.overlays // []) + $ad) | unique) | .offered = (($was + $off + $ad) | unique)' "$CONFIG" > "$tmp" \
   && mv -f "$tmp" "$CONFIG"; then
  echo "saved: overlays=$(jq -r '.overlays | join(",")' "$CONFIG") offered=$(jq -r '.offered | join(",")' "$CONFIG")"
else
  rm -f "$tmp"; echo "could not save the settings" >&2; exit 1
fi
