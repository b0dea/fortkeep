#!/bin/bash
# Adds folders that every scan must skip. Never prints the entries. Adding one hides it from every check, so it takes
# the person: right after their "Add private folder" answer to the question naming that folder (checks/ask.sh private
# add FOLDER, recorded by the approval hook), or typed by them in a terminal app. Removing one is only ever typed by them.
# Usage: checks/private.sh add PATH | remove PATH | count
if [ "${1:-}" = remove ]; then  # the person runs it: only from a signed release, checked before anything else is sourced
  . "$(dirname "$0")/lib/repo.sh"
  devward_release_gate "$(dirname "$0")/.." || exit 4
fi
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/agent.sh"
. "$(dirname "$0")/lib/approval.sh"
APPROVALS="$(cd "$(dirname "$0")/.." && pwd -P)/reports/.approvals"  # from this file's place, never the environment
count() { devward_private_list | grep -c . ; }
case "${1:-}" in
  add)
    [ -n "${2:-}" ] || { echo "usage: $0 add PATH" >&2; exit 2; }
    p="$(devward_private_folder "$2")" || { echo "use an absolute path, or one starting with ~/, without . or .. in it" >&2; exit 2; }
    # /bin/ps is fixed here on purpose: no environment variable may switch the person check off.
    if ! devward_is_person /bin/ps; then
      if devward_private_refused "$p"; then
        echo "REFUSED: that folder is /, your home folder, a folder above it, or devward's own folder. If it must be private, the person adds it in the Terminal app: checks/private.sh add \"<path>\", from this repo's folder." >&2
        exit 4
      fi
      # The answer counts only for the folder its question named (checks/ask.sh private add FOLDER).
      devward_take_approval "$APPROVALS" private add "$p" || exit 4
    fi
    printf '%s\n' "$p" >> "$DEVWARD_PRIVATE_PATHS"
    chmod 600 "$DEVWARD_PRIVATE_PATHS"
    echo "added 1 private path ($(count) total)" ;;
  remove)
    [ -n "${2:-}" ] || { echo "usage: $0 remove PATH" >&2; exit 2; }
    p="$2"
    case "$p" in '~'/*) p="$HOME/${p#\~/}" ;; esac
    p="${p%/}"
    [ -f "$DEVWARD_PRIVATE_PATHS" ] || { echo "that path is not on the list" >&2; exit 1; }
    tmp="$(mktemp "$DEVWARD_PRIVATE_PATHS.XXXXXX")" || exit 1
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      e="$line"
      case "$e" in '~'/*) e="$HOME/${e#\~/}" ;; esac
      if [ "${e%/}" = "$p" ]; then n=$((n + 1)); else printf '%s\n' "$line" >> "$tmp"; fi
    done < "$DEVWARD_PRIVATE_PATHS"
    if [ "$n" -eq 0 ]; then rm -f "$tmp"; echo "that path is not on the list" >&2; exit 1; fi
    chmod 600 "$tmp" || { rm -f "$tmp"; exit 1; }
    mv -f "$tmp" "$DEVWARD_PRIVATE_PATHS" || { rm -f "$tmp"; exit 1; }
    echo "removed $n private path(s) ($(count) total)" ;;
  count) echo "$(count) private path(s) configured" ;;
  *) echo "usage: $0 add PATH | remove PATH | count" >&2; exit 2 ;;
esac
