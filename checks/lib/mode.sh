#!/bin/bash
# Source it, don't run it. Which mode fortkeep runs in: the test suite, a development session or a person's. Sourced by
# common.sh, repo.sh and the guards' lib.sh; it sources nothing itself.

fortkeep_under_test() {  # true only inside the test suite: bats runs this, its per-test folder holds the helpers'
  # marker, and HOME is below that folder
  local t
  [ -n "${BATS_TEST_TMPDIR:-}" ] && [ -f "$BATS_TEST_TMPDIR/.fortkeep-test" ] || return 1
  case "$HOME" in "$BATS_TEST_TMPDIR"/?*) ;; *) return 1 ;; esac  # strictly below: the folder can't be HOME itself
  # The variables can come from a planted agent config, and the marker from the agent's own write tools. What neither
  # can make is a process tree: a person's agent runs only fortkeep's scripts, and its commands descend from the agent,
  # never from a test runner. So bats must be an ancestor. This doesn't rest on knowing every folder an agent may write.
  fortkeep_bats_ancestor || return 1
  # A second layer: never a folder an agent in a person's session may write (its scratch folder, a plan folder).
  t="$(cd "$BATS_TEST_TMPDIR" 2>/dev/null && pwd -P)" || return 1
  case "$t/" in /private/tmp/claude-*/*|*/plans/*) return 1 ;; esac
}

fortkeep_bats_ancestor() {  # true when bats's test runner (bats-exec-file or bats-exec-test) started this shell, or an
  # ancestor of it. /bin/ps is fixed: no environment variable may choose it.
  local pid=$$ n=0 ppid args
  while [ "$n" -lt 40 ]; do
    read -r ppid args <<EOF
$(/bin/ps -o ppid=,args= -p "$pid" 2>/dev/null)
EOF
    case "$args" in */libexec/bats-core/bats-exec-file\ *|*/libexec/bats-core/bats-exec-test\ *) return 0 ;; esac
    case "$ppid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$ppid" -gt 1 ] || return 1
    pid="$ppid"; n=$((n + 1))
  done
  return 1
}

fortkeep_dev_session() {  # true in a development session: FORTKEEP_DEV=1 and the marker ~/.config/fortkeep/dev
  # The variable alone isn't enough: a planted agent config or launcher can set it for commands no guard sees. The
  # marker is a file only the person creates, outside the repo, where a person's session writes nothing. It is read
  # from the account's own home folder, so a changed HOME can't point at a planted one. The test suite uses the
  # marker in its own temporary HOME, never the real one.
  local home
  [ "${FORTKEEP_DEV:-}" = 1 ] || return 1
  home="$(fortkeep_home)" && [ -f "$home/.config/fortkeep/dev" ]
}

fortkeep_home() {  # prints the account's own home folder, from the directory service, so a changed HOME can't point
  # fortkeep at planted files; the test suite's HOME under the suite. Status 1, with a message, when it can't be read.
  local home
  if fortkeep_under_test; then home="$HOME"; else home="$(/usr/bin/perl -e 'print +(getpwuid($<))[7] // ""')"; fi
  [ -n "$home" ] || { echo "fortkeep: could not read your home folder from your account" >&2; return 1; }
  printf '%s\n' "$home"
}
