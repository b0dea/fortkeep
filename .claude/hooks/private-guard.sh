#!/bin/bash
# PreToolUse: refuses any tool call naming a private folder, or the private list file in a path field.
set -o pipefail
fail() { echo "Blocked by devward: guard could not read the request" >&2; exit 2; }
blocked() { echo "Blocked: that location is private to this person and is never read or reported." >&2; exit 2; }
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "$0")/lib.sh"
# shellcheck source=/dev/null
. "$REPO/checks/lib/common.sh" 2>/dev/null || fail
input="$(cat)"
[ -n "$input" ] || fail
hay="$(printf '%s' "$input" | jq -r '[.tool_input | .. | strings] | join("\n")')" || fail
# Names are compared folded, as APFS compares them (lib.sh fold): a look-alike letter opens the same file.
fields="$(printf '%s' "$input" | jq -r '[.tool_input.file_path, .tool_input.path, .tool_input.notebook_path, .tool_input.command, (if .tool_name == "Glob" then .tool_input.pattern else empty end)] | map(strings) | join("\n")' | fold)" || fail
list_re="$(basename "$DEVWARD_PRIVATE_PATHS" | fold | sed 's/[.]/\\./g')"
if grep -Eiq "(^|[^A-Za-z0-9_.-])${list_re}([^A-Za-z0-9_.-]|\$)" <<<"$fields"; then blocked; fi
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty')" || fail
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
P="$(dirname "$0")/resolve-paths.pl"
# Quotes removed, ~/ and $HOME/ expanded, relative paths resolved; folded because APFS ignores case.
expand() { perl -pe 's#["\x27]##g; s#(?:~|\$HOME|\$\{HOME\})/#$ENV{HOME}/#g'; }
lower() { fold; }
hay="$( { printf '%s\n' "$hay" | expand; printf '%s' "$hay" | CWD="$cwd" perl "$P" tokens; } | lower)" || fail
# Fix backups count as private too: they are verbatim copies of start-up files, which can hold keys.
privs="$( { devward_private_list && printf '%s\n' "$DEVWARD_BACKUPS"; } | lower)" || fail
# Search roots: Read/Grep/Glob path fields and listing/search tools in Bash. A parent of a private entry is blocked.
roots="$( {
  printf '%s' "$input" | jq -r --arg cwd "$cwd" 'select(.tool_name | IN("Read", "Grep", "Glob")) | .tool_name as $t | .tool_input
    | (.file_path, .path, (if $t == "Glob" then .pattern else empty end),
       (if $t == "Grep" and ((.path // "") == "") then $cwd else empty end)) | strings | select(length > 0)' \
    | CWD="$cwd" perl "$P" lines
  printf '%s' "$input" | jq -r 'select(.tool_name == "Bash") | .tool_input.command // empty' | CWD="$cwd" perl "$P" search-roots
} | perl -pe 's#/*$#/#' | lower)" || fail
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$hay" in *"$p"*) blocked ;; esac
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$p/" in "$r"*) blocked ;; esac
  done <<EOT
$roots
EOT
done <<EOF
$privs
EOF
exit 0
