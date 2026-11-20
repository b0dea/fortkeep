#!/bin/bash
# Shared helpers for check scripts. Source it, don't run it.

# shellcheck source=checks/lib/mode.sh
. "$(dirname "${BASH_SOURCE[0]}")/mode.sh"  # fortkeep_under_test

# Two PATHs. FORTKEEP_USER_PATH is the one the person's tools are found on, as the caller had it: checks that inspect
# it (is Safe Chain first, is a tool installed) read that. Commands fortkeep itself runs come from the system folders
# first, so a fake fdesetup earlier on the caller's PATH can't answer for the real one. Only the test suite puts its
# stub folder ahead of them.
FORTKEEP_CALLER_PATH="$PATH"
FORTKEEP_USER_PATH="${FORTKEEP_USER_PATH:-$PATH}"
if fortkeep_under_test; then PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
else PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"; fi

FORTKEEP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTKEEP_REPO="${FORTKEEP_REPO:-$(cd "$FORTKEEP_LIB_DIR/../.." && pwd)}"
FORTKEEP_SYSROOT="${FORTKEEP_SYSROOT:-}"
FORTKEEP_REPORTS="${FORTKEEP_REPORTS:-$FORTKEEP_REPO/reports}"
# Fix backups are copies of start-up files, which can hold keys, so they are private. Outside the repo, so searching
# the repo never reaches them, and outside reports/, which the agent may write to.
FORTKEEP_BACKUPS="${FORTKEEP_BACKUPS:-$HOME/.local/state/fortkeep/backups}"
FORTKEEP_PRIVATE_PATHS="${FORTKEEP_PRIVATE_PATHS:-$FORTKEEP_REPO/private-paths}"

fortkeep_clean_start() {  # SCRIPT ARGS... — starts SCRIPT again (exec) unless this environment is already clean; returns when it is
  # Clean means: no exported shell function, which `bash -p` ignores but passes on to every shell a check starts; and,
  # outside the test suite, no FORTKEEP_* setting from the caller (the tests' way to point checks at fake files) and
  # the account's own home folder. Run from a `#!/bin/bash -p` script, so BASH_ENV and ENV never ran.
  local drop=() v home="" again="${FORTKEEP_CLEAN_STARTED:-}"
  unset FORTKEEP_CLEAN_STARTED
  # The names themselves, NUL-separated: a value with a newline in it can't pose as one.
  while IFS= read -r -d '' v; do drop+=(-u "$v"); done < <(/usr/bin/perl -e 'print "$_\0" for grep /^BASH_FUNC_/, keys %ENV')
  if ! fortkeep_under_test; then
    for v in $(compgen -e); do case "$v" in FORTKEEP_*) drop+=(-u "$v") ;; esac; done
    home="$(/usr/bin/perl -e 'print +(getpwuid($<))[7] // ""')"
    [ -n "$home" ] || { echo "fortkeep: could not read your home folder from your account" >&2; exit 2; }
    [ "$home" = "$HOME" ] && home=""
  fi
  [ ${#drop[@]} -gt 0 ] || [ -n "$home" ] || return 0
  # Once only: if starting again didn't clean it, stop rather than start again for ever.
  [ -z "$again" ] || { echo "fortkeep: could not start with a clean environment" >&2; exit 2; }
  exec /usr/bin/env -u BASH_ENV -u ENV ${drop[@]+"${drop[@]}"} PATH="$FORTKEEP_CALLER_PATH" HOME="${home:-$HOME}" \
    FORTKEEP_CLEAN_STARTED=1 /bin/bash -p "$@"
}

fortkeep_result() {  # ID STATUS EVIDENCE [NOTE] — an ERROR never goes out without evidence
  local ev="$3" note="${4:-}"
  case "$2" in PASS|FAIL|NA|ERROR) ;; *) echo "fortkeep_result: bad status '$2'" >&2; return 2 ;; esac
  if [ "$2" = ERROR ] && [ -z "$ev" ]; then ev="${note:-the check could not decide}"; note=""; fi
  jq -cn --arg id "$1" --arg status "$2" --arg evidence "$ev" --arg note "$note" \
    '{id:$id, status:$status, evidence:$evidence, note:$note}'
}

fortkeep_check_verdict() {  # ID EXIT_CODE OUTPUT SECONDS — the check's own result, or the ERROR that says why there is none
  local sig
  if [ "$2" -eq 142 ]; then fortkeep_result "$1" ERROR "timed out after ${4}s" ""
  elif sig="$(fortkeep_signal_name "$2")"; then
    fortkeep_result "$1" ERROR "Something outside fortkeep stopped this check (signal $sig). It is often a security tool mistaking a read-only check for malware; ask whoever manages it for an exclusion, and never turn it off." ""
  elif jq -e --arg id "$1" 'type == "object" and .id == $id and (.status | IN("PASS","FAIL","NA","ERROR"))' >/dev/null 2>&1 <<<"$3"; then
    printf '%s\n' "$3"
  else fortkeep_result "$1" ERROR "check produced no valid result (exit $2)" ""; fi
}

fortkeep_needs_clt() {  # PROGRAM_PATH — true when it is Apple's /usr/bin stub for a developer tool and the Command Line Tools
  # are missing: running it would open their install dialog, so a check must not.
  local p
  for p in "$1" "$(fortkeep_realpath "$1")"; do
    case "$p" in /usr/bin/git|/usr/bin/python3|/usr/bin/pip3) ! xcode-select -p >/dev/null 2>&1; return ;; esac
  done
  return 1
}

fortkeep_has() { command -v "$1" >/dev/null 2>&1; }

# `defaults read` stderr for a key that was never set: "does not exist" on older macOS, "Could not find key" on newer,
# and "Domain '…' not found." when nothing in that domain was ever set.
fortkeep_defaults_unset() { case "$1" in *"does not exist"*|*"Could not find key"*|*"Domain "*" not found"*) return 0 ;; esac; return 1; }

fortkeep_join() {  # LIST [SEPARATOR] — its non-empty lines joined by SEPARATOR, a space by default
  printf '%s\n' "$1" | awk -v s="${2- }" 'length { printf "%s%s", (n++ ? s : ""), $0 } END { if (n) printf "\n" }'
}

fortkeep_count() { printf '%s\n' "$1" | grep -c . || :; }  # LIST — how many non-empty lines it has

fortkeep_realpath() {  # PATH... — each one's physical path, symlinks resolved, one per line; an empty line for one that can't be
  perl -MCwd=abs_path -le 'print abs_path($_) // "" for @ARGV' "$@"
}

fortkeep_timeout() {  # SECONDS CMD... — CMD's exit code; 142 if CMD overruns, 128+N if signal N stopped it
  # KILL, as an interactive zsh ignores TERM; also after a normal exit, so a background job can't hold the output.
  # 142 is only ever our own timeout: a CMD that an outside ALRM stopped gives 255.
  perl -e '
    my $t = shift; my $pid = fork; die "fork failed\n" unless defined $pid;
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or exit 127 }
    # STOP first: a group KILL reaches members one by one, and a shell whose child died first could run on.
    local $SIG{ALRM} = sub { kill "STOP", -$pid; kill "KILL", $pid, -$pid; exit 142 };
    alarm $t; waitpid($pid, 0); my $st = $?; alarm 0; kill "STOP", -$pid; kill "KILL", -$pid;
    my $sig = $st & 127; exit($sig == 0 ? $st >> 8 : $sig == 14 ? 255 : 128 + $sig)' "$@"
}

fortkeep_signal_name() {  # EXIT_CODE — the signal's name (KILL, TERM…) for an exit code fortkeep_timeout gave as 128+N
  case "$1" in ''|*[!0-9]*) return 1 ;; esac
  [ "$1" -gt 128 ] && [ "$1" -lt 160 ] && [ "$1" -ne 142 ] || return 1
  kill -l "$(($1 - 128))" 2>/dev/null
}

fortkeep_path() { printf '%s%s\n' "$FORTKEEP_SYSROOT" "$1"; }

fortkeep_tilde() {
  case "$1" in
    "$HOME") printf '~\n' ;;
    "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

fortkeep_private_list() {
  [ -f "$FORTKEEP_PRIVATE_PATHS" ] || return 0
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in '~'/*) line="$HOME/${line#\~/}" ;; esac
    printf '%s\n' "${line%/}"
  done < "$FORTKEEP_PRIVATE_PATHS"
}

fortkeep_fold() {  # TEXT on stdin — as APFS compares names: NFC, upper case, lower case, NFC again (the guards' fold)
  /usr/bin/perl -CSD -MUnicode::Normalize -0777 -pe '$_ = NFC(lc(uc(NFC($_))))'
}

fortkeep_is_private() {  # PATH — inside a private folder as spelled, in any letter case (APFS ignores it)
  local p f list
  list="$(fortkeep_private_list)"; [ -n "$list" ] || return 1
  f="$(printf '%s' "$1" | fortkeep_fold)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$f" in "$p"|"$p"/*) return 0 ;; esac
  done <<EOF
$(printf '%s\n' "$list" | fortkeep_fold)
EOF
  return 1
}

fortkeep_private_folder() {  # PATH — prints it as a private-list entry: absolute, ~/ expanded, no trailing slash.
  # Status 1 when it isn't absolute, holds a control character, or is spelled with ., .. or an empty part: one folder
  # has one spelling, so an answer to a question naming it can't be stretched to another.
  local p="$1"
  case "$p" in '~'/*) p="$HOME/${p#\~/}" ;; esac
  case "$p" in /*) ;; *) return 1 ;; esac
  case "$p" in *[[:cntrl:]]*) return 1 ;; esac
  p="${p%"${p##*[!/]}"}"; [ -n "$p" ] || p=/
  [ "$p" = / ] || case "$p/" in *//*|*/./*|*/../*) return 1 ;; esac
  printf '%s\n' "$p"
}

fortkeep_accept_reason() {  # REASON — true when it can be the reason for an accepted control: one line of 1 to 300
  # characters with no control characters or backslashes. The question names it and the recorded answer holds it, so
  # it stays one readable line; the guard refuses a backslash in the agent's command, so one could never be passed on.
  [ -n "$1" ] && [ "${#1}" -le 300 ] || return 1
  case "$1" in *[[:cntrl:]]*|*\\*) return 1 ;; esac
}

fortkeep_private_refused() {  # FOLDER (from fortkeep_private_folder) — true when it is /, the home folder, a folder above
  # it, or this fortkeep folder or one above it, as spelled, with symlinks resolved or by its physical path, in any letter
  # case (macOS ignores case). Hiding one of these would blind every check, so an agent's session never adds it.
  local c t home phys plib lib="$FORTKEEP_LIB_DIR/../.."
  # The account's own home as well as HOME, also under the test suite.
  home="$(/usr/bin/perl -e 'print +(getpwuid($<))[7] // ""')"
  [ -n "$home" ] || { echo "fortkeep: could not read your home folder from your account" >&2; return 0; }
  # The scanners match private folders by physical path (pwd -P), which turns the data volume's spelling
  # (/System/Volumes/Data/Users/u) into /Users/u where perl's abs_path keeps it. So compare physical paths too, and
  # each folder that must stay visible also in the data volume's spelling, so the folders above it there count.
  plib="$(cd "$lib" && pwd -P)"
  phys="$(cd "$HOME" 2>/dev/null && pwd -P)
$(cd "$home" 2>/dev/null && pwd -P)
$plib"
  for c in "$1" "$(fortkeep_realpath "$1")" "$(cd "$1" 2>/dev/null && pwd -P)"; do
    [ -n "$c" ] || continue
    c="$(printf '%s' "$c" | tr '[:upper:]' '[:lower:]')"
    [ "$c" != / ] || return 0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$(printf '%s' "$t" | tr '[:upper:]' '[:lower:]')/" in "$c"/*) return 0 ;; esac
    done <<EOF
$HOME
$home
$(fortkeep_realpath "$HOME" "$home")
$(cd "$lib" && pwd)
$phys
$(printf '%s\n' "$phys" | sed '/./s#^#/System/Volumes/Data#')
EOF
  done
  return 1
}

fortkeep_walk() {  # DIR [find tests...] [-print0] — like find, but never descends into private paths; prints with -print unless told -print0
  local dir="$1" p print=(-print)
  shift
  [ "${!#}" != -print0 ] || print=()
  local prune=()
  while IFS= read -r p; do
    # -path takes a pattern: a folder named "Client [NDA]" must match only itself. -ipath: APFS ignores letter case.
    [ -n "$p" ] && prune+=( -ipath "$(printf '%s' "$p" | sed 's/[][*?\\]/\\&/g')" -prune -o )
  done <<EOF
$(fortkeep_private_list)
EOF
  find "$dir" ${prune[@]+"${prune[@]}"} "$@" ${print[@]+"${print[@]}"} 2>/dev/null
}

fortkeep_real_cmd() {  # NAME — first NAME on the person's PATH that isn't a Safe Chain shim
  local d IFS=:
  for d in $FORTKEEP_USER_PATH; do
    case "$d" in ""|"$HOME/.safe-chain"|"$HOME/.safe-chain"/*) continue ;; esac
    if [ -x "$d/$1" ] && [ ! -d "$d/$1" ]; then printf '%s\n' "$d/$1"; return 0; fi
  done
  return 1
}

fortkeep_version_ge() {  # A B — true if dotted version A >= B
  perl -e 'my @a = split /\./, $ARGV[0]; my @b = split /\./, $ARGV[1];
    for my $i (0 .. 2) { my ($x, $y) = ($a[$i] // "0", $b[$i] // "0");
      ($x) = $x =~ /^(\d*)/; ($y) = $y =~ /^(\d*)/; $x ||= 0; $y ||= 0;
      exit 0 if $x > $y; exit 1 if $x < $y } exit 0' "$1" "$2"
}
