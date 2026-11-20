#!/bin/bash
# Source it, don't run it. Whether this copy of the repo is exactly a signed release. Scripts source it and check the
# copy before they source anything else; it sources only mode.sh beside it, which sources nothing.
# shellcheck source=checks/lib/mode.sh
. "$(dirname "${BASH_SOURCE[0]}")/mode.sh"  # fortkeep_dev_session

# The copy's own git config and refs are untrusted: no replace refs, fsmonitor or filters.
fortkeep_git() {  # REPO ARGS... — git in REPO
  local r="$1"; shift
  git --no-replace-objects -C "$r" -c core.fsmonitor= "$@"
}

fortkeep_releases() {  # REPO — its release tags (v1.2.3), newest version first
  fortkeep_git "$1" tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'
}

# A release tag's message is "<this name> <tag>", so a tag a maintainer signed for another repo is no release here.
FORTKEEP_RELEASE_NAME="b0dea/fortkeep"

fortkeep_release_signed() {  # REPO TAG SIGNERS — true when TAG is a release of this repo that a key in the SIGNERS file signed
  # The signed tag object must carry TAG's own name and this repo's: an older release pushed again under a newer
  # name, or a tag signed for another repo, is refused. Only SSH signatures count, checked with the stock
  # ssh-keygen whatever the person's git config says.
  local r="$1" t="$2"
  [ "$(fortkeep_git "$r" for-each-ref --format='%(objecttype) %(tag) %(contents:subject)' "refs/tags/$t")" = "tag $t $FORTKEEP_RELEASE_NAME $t" ] || return 1
  fortkeep_git "$r" -c gpg.program=/usr/bin/false -c gpg.openpgp.program=/usr/bin/false -c gpg.x509.program=/usr/bin/false \
    -c gpg.ssh.program=/usr/bin/ssh-keygen -c gpg.ssh.allowedSignersFile="$3" verify-tag "refs/tags/$t" >/dev/null 2>&1
}

fortkeep_local_changes() {  # REPO — true unless every tracked file matches HEAD in content, type and executable bit, and no
  # untracked file sits where an agent loads its instructions, hooks, skills or plugins
  local r="$1" tree meta path mode obj f files="" want="" extra
  extra="$(fortkeep_git "$r" -c core.quotePath=false ls-files --others --exclude-standard -- \
    .claude .codex .opencode .agents opencode.json AGENTS.md CLAUDE.md 2>/dev/null)" || return 0
  [ -z "$extra" ] || return 0
  tree="$(fortkeep_git "$r" -c core.quotePath=false ls-tree -r HEAD 2>/dev/null)" || return 0
  while IFS=$'\t' read -r meta path; do
    [ -n "$meta" ] || continue
    mode="${meta%% *}"; obj="${meta##* }"; f="$r/$path"
    case "$path" in '"'*) return 0 ;; esac  # a name git had to quote isn't compared: counts as changed
    case "$mode" in
      160000) ;;
      120000) [ -L "$f" ] && [ "$(printf '%s' "$(readlink "$f")" | fortkeep_git "$r" hash-object --no-filters --stdin)" = "$obj" ] || return 0 ;;
      100644|100755)
        [ -f "$f" ] && [ ! -L "$f" ] || return 0
        if [ -x "$f" ]; then [ "$mode" = 100755 ] || return 0; else [ "$mode" = 100644 ] || return 0; fi
        files="$files$path"$'\n'; want="$want$obj"$'\n' ;;
      *) return 0 ;;
    esac
  done <<EOF
$tree
EOF
  [ "$(printf '%s' "$files" | fortkeep_git "$r" hash-object --no-filters --stdin-paths 2>/dev/null)" != "$(printf '%s' "$want")" ]
}

fortkeep_config_extras() {  # REPO — one line for each file or setting, beyond the tracked files, that changes what an agent
  # loads or what git runs here: untracked or ignored files where agents load config, git hooks, local git settings
  # that run commands. Ignored files count: an agent loads them as readily as tracked ones. OpenCode installs its
  # plugin library in .opencode itself (node_modules, package.json, bun.lock, .gitignore); none of it is a plugin.
  local r="$1" d f
  fortkeep_git "$r" -c core.quotePath=false ls-files --others -- .claude .codex .agents .opencode \
    ':(exclude).opencode/node_modules' ':(exclude).opencode/package.json' ':(exclude).opencode/bun.lock' \
    ':(exclude).opencode/.gitignore' opencode.json opencode.jsonc .mcp.json \
    ':(glob)**/CLAUDE.md' ':(glob)**/CLAUDE.local.md' ':(glob)**/AGENTS.md' ':(glob)**/AGENTS.override.md' 2>/dev/null \
    || { echo "files: unreadable"; return 0; }
  # The copy's own hook folder. A hook folder from the person's own git config is theirs, not the copy's, and fortkeep's
  # own git commands run with no hooks; a core.hooksPath in the copy's config is listed below as a setting.
  d="$(fortkeep_git "$r" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/hooks" || { echo "git hooks: unreadable"; return 0; }
  for f in "$d"/*; do
    case "$f" in *.sample) continue ;; esac
    if [ -e "$f" ] || [ -L "$f" ]; then printf 'git hook %s\n' "${f##*/}"; fi
  done
  d="$(fortkeep_git "$r" rev-parse --path-format=absolute --git-path info/attributes 2>/dev/null)" || { echo "git attributes: unreadable"; return 0; }
  [ ! -s "$d" ] || echo "git info/attributes"
  # The copy's own settings, its worktree-only ones included: none that runs a command or swaps what git reads. A url
  # or credential setting's middle part is an address, which can carry a token: it is never printed.
  fortkeep_git "$r" config --list --includes --show-scope --name-only 2>/dev/null \
    | awk -F'\t' '$1 == "local" || $1 == "worktree" { print $2 }' \
    | grep -E '^(core\.(hookspath|fsmonitor|sshcommand|askpass|attributesfile|gitproxy|worktree)|hook\..*|filter\..*|credential\..*|url\..*|remote\..*\.uploadpack|include\..*|includeif\..*)$' \
    | sed -E -e 's/^(url|credential)\..+\.([^.]+)$/\1.*.\2/' -e 's/^/git setting /'
}

fortkeep_version_lt() {  # A B — true when release A (v1.2.3) is older than release B
  local a="${1#v}." b="${2#v}." x y
  for _ in 1 2 3; do
    x="${a%%.*}"; y="${b%%.*}"; a="${a#*.}"; b="${b#*.}"
    [ "$x" -lt "$y" ] && return 0
    [ "$x" -gt "$y" ] && return 1
  done
  return 1
}

fortkeep_is_version() { printf '%s\n' "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; }

# What this Mac records about the releases it ran lives in the account's own home folder (fortkeep_home), never under
# a HOME something else set, so a changed HOME can't swap in another record.
fortkeep_state_file() {  # NAME — prints ~/.config/fortkeep/NAME in that folder
  local h; h="$(fortkeep_home)" || return 1
  printf '%s\n' "$h/.config/fortkeep/$1"
}

# The signers this Mac trusts for releases, kept outside the copy: those of the first release it ran, then those of
# each newer release one of them vouched for. A release can't add its own signer and vouch for itself.
fortkeep_trusted_signers_file() { fortkeep_state_file release-signers; }

fortkeep_signers_to() {  # REPO REV FILE — writes the signers this Mac trusts into FILE, or, before it trusts any, the
  # signers list of commit REV (never the working tree); status 1 when it can't tell which
  local t; t="$(fortkeep_trusted_signers_file)" || return 1
  if [ -s "$t" ]; then cat "$t" > "$3"
  else fortkeep_git "$1" cat-file blob "$2:.github/allowed_signers" > "$3" 2>/dev/null || : > "$3"; fi
}

fortkeep_verify_release() {  # REPO — true when HEAD is exactly a release signed by a key this Mac trusts
  # (fortkeep_signers_to), and nothing has changed since: no tracked file and no config file fortkeep_config_extras
  # lists. Sets FORTKEEP_RELEASE_TAG to the release, or FORTKEEP_RELEASE_PROBLEM to why not. Status 2 when why not is
  # a local change.
  local r="$1" head t signers ok extras
  FORTKEEP_RELEASE_TAG=""; FORTKEEP_RELEASE_PROBLEM=""
  head="$(fortkeep_git "$r" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)" \
    || { FORTKEEP_RELEASE_PROBLEM="it is not a git checkout"; return 1; }
  extras="$(fortkeep_config_extras "$r")"
  if [ -n "$extras" ]; then
    FORTKEEP_RELEASE_PROBLEM="it has local changes: $(printf '%s\n' "$extras" | head -n 3 | paste -sd, - | sed 's/,/, /g')"
    return 2
  fi
  if fortkeep_local_changes "$r"; then FORTKEEP_RELEASE_PROBLEM="it has local changes to its files"; return 2; fi
  signers="$(mktemp "${TMPDIR:-/tmp}/fortkeep-signers.XXXXXX")" || { FORTKEEP_RELEASE_PROBLEM="a temporary file could not be made"; return 1; }
  fortkeep_signers_to "$r" "$head" "$signers" \
    || { rm -f "$signers"; FORTKEEP_RELEASE_PROBLEM="the signers this Mac trusts could not be read"; return 1; }
  for t in $(fortkeep_git "$r" tag --points-at "$head" --list 'v*' --sort=-v:refname 2>/dev/null); do
    fortkeep_is_version "$t" || continue
    if fortkeep_release_signed "$r" "$t" "$signers"; then ok="$t"; break; fi
  done
  rm -f "$signers"
  [ -n "${ok:-}" ] || { FORTKEEP_RELEASE_PROBLEM="it is not on a signed release"; return 1; }
  FORTKEEP_RELEASE_TAG="$ok"
}

fortkeep_verify_clone() {  # REPO TAG COMMIT — true when REPO is a new clone that a first install may trust: HEAD and
  # TAG are both COMMIT, TAG is a release signed by a key COMMIT's own .github/allowed_signers lists, and nothing in it
  # would count as a local change (fortkeep_local_changes, fortkeep_config_extras). Sets FORTKEEP_CLONE_PROBLEM to why not.
  local r="$1" t="$2" c="$3" head tagged signers extras
  FORTKEEP_CLONE_PROBLEM=""
  head="$(fortkeep_git "$r" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null)"
  tagged="$(fortkeep_git "$r" rev-parse -q --verify "refs/tags/$t^{commit}" 2>/dev/null)"
  if [ "$head" != "$c" ] || [ "$tagged" != "$c" ]; then
    FORTKEEP_CLONE_PROBLEM="$t is commit ${tagged:-unknown}, not the pinned $c"; return 1
  fi
  signers="$(mktemp "${TMPDIR:-/tmp}/fortkeep-signers.XXXXXX")" || { FORTKEEP_CLONE_PROBLEM="a temporary file could not be made"; return 1; }
  if ! fortkeep_git "$r" cat-file blob "$c:.github/allowed_signers" > "$signers" 2>/dev/null; then
    FORTKEEP_CLONE_PROBLEM="$t has no .github/allowed_signers"
  elif ! fortkeep_release_signed "$r" "$t" "$signers"; then
    FORTKEEP_CLONE_PROBLEM="$t is not signed by a maintainer its own .github/allowed_signers lists"
  elif fortkeep_local_changes "$r"; then
    FORTKEEP_CLONE_PROBLEM="the clone of $t differs from its commit"
  else
    extras="$(fortkeep_config_extras "$r")"
    [ -z "$extras" ] || FORTKEEP_CLONE_PROBLEM="fortkeep would treat this copy as changed, because of this Mac's git settings: $(printf '%s\n' "$extras" | paste -sd, - | sed 's/,/, /g')"
  fi
  rm -f "$signers"
  [ -z "$FORTKEEP_CLONE_PROBLEM" ]
}

# The highest release this Mac has run, so that going back to an older one (with its fixed bugs) warns.
fortkeep_highest_file() { fortkeep_state_file highest-release; }

fortkeep_downgrade_from() {  # TAG — prints the highest release recorded on this Mac when TAG is older than it
  local f h
  f="$(fortkeep_highest_file)" || return 1
  [ -f "$f" ] || return 1
  h="$(head -n 1 "$f")"
  fortkeep_is_version "$h" && fortkeep_version_lt "$1" "$h" || return 1
  printf '%s\n' "$h"
}

# Where this Mac's copy fetches releases from, recorded at its first verified install: checks/update.sh fetches from
# nowhere else, so a copy pointed at a mirror that holds other tags is refused.
fortkeep_origin_file() { fortkeep_state_file origin; }

fortkeep_origin_url() {  # REPO — prints its one remote.origin.url; status 1 when it has none, or several
  local u
  u="$(fortkeep_git "$1" config --get-all remote.origin.url 2>/dev/null)" || return 1
  case "$u" in ''|*$'\n'*) return 1 ;; esac
  printf '%s\n' "$u"
}

fortkeep_origin_rewritten() {  # REPO URL — true unless git fetches and pushes origin at exactly URL. A url.<base>.insteadOf
  # or pushInsteadOf setting, in the copy's config or the person's own, rewrites the address git really uses; git
  # remote get-url applies both, as a fetch would.
  local f p
  f="$(fortkeep_git "$1" remote get-url origin 2>/dev/null)" && p="$(fortkeep_git "$1" remote get-url --push origin 2>/dev/null)" || return 0
  [ "$f" != "$2" ] || [ "$p" != "$2" ]
}

fortkeep_note_release() {  # TAG REPO — for a release that verified: records TAG as the highest release this Mac has run
  # and its signers as the ones trusted from now on, unless a higher release is recorded; and, the first time, where
  # the copy fetches from
  local f h="" s o u
  o="$(fortkeep_origin_file)" && f="$(fortkeep_highest_file)" && s="$(fortkeep_trusted_signers_file)" || return 1
  if [ ! -s "$o" ] && u="$(fortkeep_origin_url "$2")"; then
    { mkdir -p "${o%/*}" && printf '%s\n' "$u" > "$o.$$" && mv -f "$o.$$" "$o"; } \
      || { rm -f "$o.$$"; echo "could not record where this copy fetches from in $o" >&2; return 1; }
  fi
  [ ! -f "$f" ] || h="$(head -n 1 "$f")"
  if fortkeep_is_version "$h" && fortkeep_version_lt "$1" "$h"; then return 0; fi
  { mkdir -p "${f%/*}" && printf '%s\n' "$1" > "$f.$$" && mv -f "$f.$$" "$f" \
      && fortkeep_git "$2" cat-file blob "refs/tags/$1^{commit}:.github/allowed_signers" > "$s.$$" && mv -f "$s.$$" "$s"; } \
    || { rm -f "$f.$$" "$s.$$"; echo "could not record $1 as the highest release in $f" >&2; return 1; }
}

fortkeep_release_gate() {  # REPO — for fix scripts and the scripts a person runs: status 0 when REPO is exactly a
  # signed release (recorded as run, with a warning on a downgrade); otherwise prints why and returns 1.
  # A development session (fortkeep_dev_session: FORTKEEP_DEV=1 and the person's marker) passes on an untagged tree,
  # and so does the test suite, which makes its own marker. The agent in a person's session can't set the variable
  # (the allow-list refuses assignments, env and every other program) nor write the marker.
  local old
  ! fortkeep_dev_session || return 0
  if ! fortkeep_verify_release "$1"; then
    echo "REFUSED: this copy of fortkeep is not exactly a signed release: $FORTKEEP_RELEASE_PROBLEM. Reinstall a signed release first." >&2
    return 1
  fi
  if old="$(fortkeep_downgrade_from "$FORTKEEP_RELEASE_TAG")"; then
    echo "WARNING: this copy is $FORTKEEP_RELEASE_TAG, older than $old, which this Mac ran before. Update with checks/update.sh unless you went back on purpose." >&2
  else
    fortkeep_note_release "$FORTKEEP_RELEASE_TAG" "$1" || :
  fi
}
