#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=BL-AI-05
# One line per server: pinned|unpinned|other <TAB> name. Arguments and env (which can hold tokens) never leave jq.
classify='
def runner: (.command // "" | tostring | split("/") | last) as $c | (.args // [] | map(tostring)) as $a
  | if ($c | IN("npx", "bunx", "pnpx")) then {k: "npm", a: $a}
    elif $c == "uvx" then {k: "uv", a: $a}
    elif $c == "pipx" then {k: "pipx", a: (if $a[0] == "run" then $a[1:] else $a end)}
    elif ($c | IN("pnpm", "yarn")) and ($a[0] == "dlx") then {k: "npm", a: $a[1:]}
    elif $c == "npm" and ($a[0] | IN("exec", "x")) then {k: "npm", a: $a[1:]}
    else null end;
def specflags: {npm: ["--package", "-p"], uv: ["--from"], pipx: ["--spec"]};
def valflags: ["--registry", "--cache", "--userconfig", "--python", "-p", "--with", "--index", "--index-url",
  "--default-index", "--extra-index-url", "--pip-args", "-c", "--call"];
def pkg: .k as $k | .a as $a
  | ([range(0; $a | length) as $i | select($a[$i] | IN(specflags[$k][])) | $a[$i + 1] // empty] | .[0])
    // (reduce $a[] as $x ({skip: false, out: []};
          if .skip then .skip = false
          elif ($x | IN(valflags[])) then .skip = true
          elif ($x | startswith("-")) then .
          else .out += [$x] end) | .out[0])
    // "";
# npm reads pkg@1 or pkg@1.2 as a range, so it needs all three numbers; the Python == is exact as written.
def pinned($k): (if $k == "npm" then test("^(@[^/@]+/)?[^@]+@[0-9]+\\.[0-9]+\\.[0-9]+")
  else test("^(@[^/@]+/)?[^@=]+(@|==)[0-9]") end) and (test("@latest$") | not);
[(.mcpServers // {}), (.projects // {} | .[]? | .mcpServers // {})] | map(to_entries[]) | .[]
| (.value | if type == "object" then runner else null end) as $a
| (if $a == null then "other" elif ($a | pkg | pinned($a.k)) then "pinned" else "unpinned" end) + "\t" + .key'
srcs="$(fortkeep_claude_states)"
mm="$(dirname "$(fortkeep_managed_settings)")/managed-mcp.json"; [ -f "$mm" ] && srcs="$srcs"$'\n'"$mm"
priv=""; c="$HOME/.cursor/mcp.json"
if fortkeep_is_private "$c"; then priv=" (a private folder was excluded)"
elif [ -f "$c" ]; then srcs="$srcs"$'\n'"$c"; fi
pnote() { local n; n="$(fortkeep_claude_note "$1")"; case "$n" in *"private folder was excluded"*) ;; *) n="$n$priv" ;; esac; printf '%s' "${n# }"; }
rows=""; unread=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  r="$(jq -r "$classify" "$f" 2>/dev/null)" || { unread="$unread $(fortkeep_tilde "$f")"; continue; }
  [ -n "$r" ] && rows="$rows$r"$'\n'
done <<EOF
$srcs
EOF
np="$(printf '%s' "$rows" | awk -F'\t' '$1 == "pinned"' | grep -c .)"
nu="$(printf '%s' "$rows" | awk -F'\t' '$1 == "unpinned"' | grep -c .)"
all="$(printf '%s' "$rows" | grep -c .)"
names="$(printf '%s' "$rows" | awk -F'\t' '$1 == "unpinned" && !s[$2]++ {print $2}' | paste -sd, - | sed 's/,/, /g')"
if [ "$nu" -gt 0 ]; then
  note="Not pinned: $names"; [ -z "$unread" ] || note="$note. Could not read:$unread"
  fortkeep_result "$ID" FAIL "$np of $((np + nu)) package-run MCP servers are pinned to a version" "$(pnote "$note")"
elif [ -n "$unread" ]; then fortkeep_result "$ID" ERROR "Could not read:$unread" "$(pnote "")"
elif [ "$all" -eq 0 ] && fortkeep_claude_private_skipped; then fortkeep_claude_excluded_error "$ID"
elif [ "$all" -eq 0 ] && [ -n "$priv" ]; then fortkeep_result "$ID" ERROR "Could not check Cursor's MCP servers" "a private folder was excluded"
elif [ "$all" -eq 0 ]; then fortkeep_result "$ID" NA "No MCP servers configured"
elif [ "$np" -eq 0 ]; then fortkeep_result "$ID" PASS "$all MCP server(s), none started from a package registry" "$(pnote "")"
else fortkeep_result "$ID" PASS "All $np package-run MCP servers are pinned to a version" "$(pnote "")"; fi
