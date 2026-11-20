#!/bin/bash
# Source it, don't run it. Shared by the guards: refusals, physical paths compared as APFS compares them, and the
# agent's own scratch, plan and memory folders. The caller sets cwd (the request's working folder) before real().
block() { echo "Blocked by fortkeep: $1" >&2; exit 2; }
HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="${CLAUDE_PROJECT_DIR:-$(cd "$HOOKS/../.." && pwd)}"
# shellcheck source=checks/lib/mode.sh
. "$HOOKS/../../checks/lib/mode.sh"  # fortkeep_dev_session: FORTKEEP_DEV=1 and the person's marker

fold() {  # TEXT on stdin — as APFS compares names: NFC, upper case, lower case, NFC again (as cockpit does), so a
  # look-alike such as U+017F (long s) or the Kelvin sign compares equal to the letter it opens
  perl -CSD -MUnicode::Normalize -0777 -pe '$_ = NFC(lc(uc(NFC($_))))'
}

ascii() { printf '%s' "$1" | LC_ALL=C perl -0777 -ne 'exit(/[^\x20-\x7e]/ ? 1 : 0)'; }  # TEXT — printable ASCII only, one line

real() {  # PATH — its physical path, folded: the deepest folder that exists resolved with pwd -P, plus the rest, after
  # following a symlink leaf (also a dangling one, at most 40 hops). Relative paths, ~ and $HOME resolve against $cwd.
  local p rest="" t hops=0
  p="$(printf '%s\n' "$1" | CWD="${cwd:-$REPO}" perl "$HOOKS/resolve-paths.pl" exact)" || return 1
  while [ -L "$p" ]; do
    hops=$((hops + 1)); [ "$hops" -le 40 ] || return 1
    t="$(readlink "$p")" || return 1
    case "$t" in /*) ;; *) t="$(dirname "$p")/$t" ;; esac
    p="$(printf '%s\n' "$t" | CWD=/ perl "$HOOKS/resolve-paths.pl" exact)" || return 1
  done
  while [ ! -d "$p" ]; do rest="/$(basename "$p")$rest"; p="$(dirname "$p")"; done
  printf '%s%s\n' "$(cd "$p" && pwd -P)" "$rest" | fold
}

agent_dirs() {  # read|write|dev — the agent's own folders, physical and folded, one per line ending in /: this
  # project's scratch folder; for reads its project folder (memory, tool results); for writes the plan folder, and in a
  # development session (dev) the project's memory too. A person's session never writes memory: what lands there
  # becomes standing instructions for every later session. The plan folder and the rest of the scratch folder hold
  # every project's files, so they aren't read.
  local d enc
  # Claude Code names a project's folders after its path, every character but a letter or digit turned into -.
  enc="$(printf '%s' "$REPO" | sed 's/[^A-Za-z0-9]/-/g' | fold)"
  printf '%s\n' "/private/tmp/claude-$(id -u)/$enc/"
  for d in "${CLAUDE_CONFIG_DIR:-}" "$HOME/.claude"; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    d="$(real "$d")"
    case "$1" in
      read) printf '%s/projects/%s/\n' "$d" "$enc" ;;
      write) printf '%s/plans/\n' "$d" ;;
      dev) printf '%s/plans/\n%s/projects/%s/memory/\n' "$d" "$d" "$enc" ;;
    esac
  done
}

read_ok() {  # PATH file|root — refuses unless a person's session may read PATH (file) or search it (root): inside
  # this checkout or the agent's own folders, never private-paths, the approval tokens or .git; a search root must not
  # hold them either. Private folders are outside the checkout, so no name comparison is left to fool.
  local t rel f repo
  [ -n "$1" ] || block "guard could not read the path"
  ascii "$1" || block "non-ASCII characters are refused in a person's session"
  repo="$(real "$REPO")" || block "guard could not find this repo"
  t="$(real "$1")" || block "guard could not resolve $1"
  under "$t" "$(agent_dirs read)" && return 0
  case "$t/" in "$repo/"*) ;; *) block "in a person's session the agent reads only this repo's files and its own folders" ;; esac
  rel="${t#"$repo"}"; rel="${rel#/}"
  # The names .gitignore keeps out as secrets: a person may keep one here, and the agent shows counts, never values.
  case "/$rel" in */.env|*/.env.*|*.pem|*.key|*/id_*)
    case "$rel" in *.example) ;; *) block "a file that may hold a secret (.env, a key) is never read in a person's session: the person opens it themselves" ;; esac ;;
  esac
  [ "$2" = file ] || [ -n "$rel" ] || block "search a folder inside this repo, not all of it: it holds private-paths and .git"
  for f in private-paths reports/.approvals .git; do
    case "$rel/" in "$f/"*) block "private-paths, the approval tokens and .git are never read" ;; esac
    if [ "$2" = root ]; then
      case "$f/" in "$rel/"*) block "that folder holds private-paths, the approval tokens or .git: search a folder inside it" ;; esac
    fi
  done
}

under() {  # PATH FOLDERS — true when the physical PATH is inside one of FOLDERS (lines ending in /)
  local a
  while IFS= read -r a; do
    [ -n "$a" ] || continue
    case "$1/" in "$a"*) return 0 ;; esac
  done <<EOF
$2
EOF
  return 1
}
