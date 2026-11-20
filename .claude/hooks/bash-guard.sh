#!/bin/bash
# PreToolUse(Bash) in a development session, through guard.sh: blocks sudo, pipe-to-shell and forging approvals.
# Pattern matching, not a sandbox: a person's session uses the allow-list instead.
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "$0")/lib.sh"
input="$(cat)"
[ -n "$input" ] || block "guard could not read the request"
# Codex may name it cmd, or send a list of words: those are checked joined.
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // "" | if type == "array" then join(" ") else . end')" \
  || block "guard could not read the request"
# APFS opens a look-alike letter (U+017F long s, the Kelvin sign) as the letter it folds to, so a command with
# non-ASCII text is also checked folded as APFS compares names; either form can refuse it.
if ! printf '%s' "$cmd" | LC_ALL=C perl -0777 -ne 'exit(/[^\x00-\x7f]/ ? 1 : 0)'; then
  folded="$(printf '%s' "$cmd" | fold)"
  if [ "$folded" != "$cmd" ]; then
    jq -cn --arg c "$folded" '{tool_name: "Bash", tool_input: {command: $c}}' | "$0" || exit "$?"
  fi
fi
# Join backslash-continued and multi-line commands so patterns see one line.
norm="${cmd//\\$'\n'/ }"
norm="${norm//$'\n'/ }"
if printf '%s' "$norm" | grep -Eq '(^|[;&|(`[:space:]])sudo([[:space:]]|$)'; then
  block "The agent never runs sudo. Give the person the exact command to type in the Terminal app, not in this chat."
fi
# Quotes removed, so "curl", "/usr/bin/curl" and $(command -v curl) are seen as curl too.
nq="$(printf '%s' "$norm" | tr -d "\"'")"
if printf '%s' "$nq" | grep -Eq '(^|[^A-Za-z0-9_.-])(curl|wget)([[:space:])]|$)'; then
  sh_re='(/bin/|/usr/bin/|env )?(ba|z|da|k)?sh([[:space:]]|$)'
  if printf '%s' "$nq" | grep -Eq "(curl|wget)([[:space:])]|\$).*\|[[:space:]]*$sh_re" ||
     printf '%s' "$nq" | grep -Eq '(^|[^A-Za-z0-9_])(ba|z|da|k)?sh[[:space:]]+-c.*(\$\(|`).*(curl|wget)' ||
     printf '%s' "$nq" | grep -Eq '<\(.*(curl|wget)'; then
    block "piping a download into a shell is not allowed"
  fi
fi
# A fix script runs as-is: no assignments or env in front of it. fix.sh ignores the
# environment anyway; this stops the attempt early with a clear message.
q="'"; val="([^[:space:]${q}\"]|${q}[^${q}]*${q}|\"[^\"]*\")*"  # a word, or whole quoted strings
start="(^|[;&|\`]|(^|[;&|(\`\$])[[:space:]]*\()"  # a ( counts only where a subshell starts, not in f(b=...)
fx_run="${start}[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=$val|env([[:space:]]+-[^[:space:]]+)*)[[:space:]]+)+[^;&|]*fixes/"
if printf '%s' "$norm" | grep -Eq "$fx_run" ||
   { printf '%s' "$norm" | grep -q 'fixes/' && printf '%s' "$norm" | grep -Eq '(^|[;&|(`[:space:]])export[[:space:]]+(FORTKEEP|FX)_'; }; then
  block "fix scripts run only as-is, right after the person's answer"
fi
# Bash writes to the files fix scripts own: no redirect into one, and a segment that names one
# must start with a read-only command. Edits elsewhere are already stopped by write-guard.
dend='([/[:space:];&|)*?]|\[|$)'  # a folder name ends here: slash, separator, glob or end
rc='\.zshrc|\.zprofile|\.zshenv|\.zlogin|\.bashrc|\.bash_profile|/\.profile|\.gitconfig|/\.config/git'"$dend"'|/\.ssh'"$dend"'|/LaunchAgents'"$dend"'|/\.config/fortkeep'"$dend"'|/\.claude/settings[^/]*\.json|\.claude\.json|reports/knockknock'"$dend"
ro_leader() {  # WORD — true for a command that only reads the paths it names
  case "$1" in
    cat|head|tail|less|more|grep|egrep|fgrep|rg|diff|cmp|ls|stat|file|wc|shasum|md5|readlink|realpath|du|test|\[|echo|printf|source|.|checks/private.sh|checks/accept.sh) return 0 ;;
  esac
  return 1
}
# shellcheck disable=SC2329 # called through rc_seg
gitcfg_write() {  # SEGMENT — true for git config writing the global, system or a named file (reads pass)
  local w st=0 scope=0 rd=0
  set -f
  # shellcheck disable=SC2086 # split into words on purpose
  for w in $1; do
    case "$st" in
      0) case "$w" in git|*/git) st=1 ;; esac; continue ;;
      1) case "$w" in -C|-c|--git-dir|--work-tree|--namespace|--exec-path|--config-env) st=2 ;; -*) ;; config) st=3 ;; *) break ;; esac; continue ;;
      2) st=1; continue ;;
      3) case "$w" in get|list) rd=1 ;; esac; st=4 ;;
    esac
    case "$w" in --gl*|--sy*|--fil*|-f) scope=1 ;; --get|--get-*|--list|-l|--show-origin) rd=1 ;; esac  # git takes unique prefixes
  done
  set +f
  [ "$st" -ge 3 ] && [ "$scope" -eq 1 ] && [ "$rd" -eq 0 ]
}
cp_dest() {  # SEGMENT — the last word of a cp command, past a trailing comment and redirects
  local w out="" skip=0
  set -f
  # shellcheck disable=SC2086 # split into words on purpose
  for w in ${1%%[[:space:]]#*}; do
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$w" in *[\<\>]) skip=1 ;; *[\<\>]*) ;; *) out="$w" ;; esac
  done
  set +f
  printf '%s' "$out"
}
segs="$(printf '%s' "$cmd" | tr -d "\"'\\\\")"
unq="${norm//[\"\'\\]/}"  # quotes and backslashes removed: ac''cept and "accept" still match
guard_path() {  # RE MSG [SEGFN] — no redirect into a path matching RE, no xargs or substitution near one, and a
  # segment that names one must start with a read-only command; SEGFN SEGMENT may block first.
  local seg dst
  printf '%s' "$segs" | grep -Eiq ">[>|]?[[:space:]]*[^[:space:];&|]*($1)" && block "$2"
  # xargs or a substitution could hand one of those paths to any command.
  printf '%s' "$segs" | grep -Eiq "$1" && printf '%s' "$segs" | grep -Eq '(^|[^A-Za-z0-9_])xargs([^A-Za-z0-9_]|$)|\$\(|`' && block "$2"
  # shellcheck disable=SC2020 # six separators, one newline each
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    ro_leader "${seg%%[[:space:]]*}" && continue
    if [ -n "${3:-}" ]; then "$3" "$seg"; [ "$?" -ne 3 ] || continue; fi  # 3: SEGFN clears this segment
    printf '%s' "$seg" | grep -Eiq "$1" || continue
    case "${seg%%[[:space:]]*}" in
      cp) case " $seg " in *" -t"*|*" --target-directory"*) ;; *) dst="$(cp_dest "$seg")"; case "$dst" in -*|'') ;; *) printf '%s' "$dst" | grep -Eiq "$1" || continue ;; esac ;; esac ;;
    esac
    block "$2"
  done <<EOF
$(printf '%s' "$segs" | tr ';&|()`' '\n\n\n\n\n\n')
EOF
}
# ~/.config/fortkeep holds what only the person may change: the accepted baselines, among others.
tmsg="files in ~/.config/fortkeep change only when the person runs checks/baseline.sh accept in the Terminal app"
commit_ok() {  # SEGMENT — a plain git commit without variables: its words are a message or repo paths
  case "$1 " in 'git commit '*) case "$1" in *'$'*) return 1 ;; esac; return 0 ;; esac
  return 1
}
# Two parses, one segment per line, quotes and backslashes removed, lower case (the Mac's disk ignores case):
# backslash-newline joined, and split at every newline. A check refuses if either parse trips it.
lj="${cmd//\\$'\n'/ }"; lj="${lj//[\"\'\\]/}"; ln="${cmd//[\"\'\\]/}"
# shellcheck disable=SC2020 # six separators, one newline each
lsegs_j="$(printf '%s' "$lj" | tr ';&|()`' '\n\n\n\n\n\n' | tr '[:upper:]' '[:lower:]')"
# shellcheck disable=SC2020 # six separators, one newline each
lsegs_n="$(printf '%s' "$ln" | tr ';&|()`' '\n\n\n\n\n\n' | tr '[:upper:]' '[:lower:]')"
cc_re='(^|[^a-z0-9_])((env|unset|export|declare|typeset|readonly|local)[[:space:]]([^;&|]*[^a-z0-9_$])?|env[[:space:]][^;&|]*-u[[:space:]]*)claudecode([^a-z0-9_]|$)|(^|[^a-z0-9_$])claudecode[[:space:]]*:?='
cc_check() {  # SEGMENTS
  local seg
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"
    commit_ok "$seg" && continue
    printf '%s' "$seg" | grep -Eq "$cc_re" && block "CLAUDECODE tells checks/baseline.sh it runs inside Claude Code; it stays set here"
  done <<EOF
$1
EOF
}
cc_check "$lsegs_j"; cc_check "$lsegs_n"
pin_names() {  # COMPONENT NAME — true when the component is NAME, or a glob or brace that could match it
  # shellcheck disable=SC2254 # $1 is a pattern on purpose
  case "$1" in "$2"|*'{'*,*'}'*|*'{'*..*'}'*) return 0 ;; *[*?[]*) case "$2" in $1) return 0 ;; esac ;; esac
  return 1
}
hlc="$(printf '%s' "$HOME" | tr '[:upper:]' '[:lower:]')"
pin_word() {  # WORD — true when the lower-case word could name ~/.config/fortkeep or ~/.config
  local c prev=start last="" lastprev="" IFS=/ var='*[$`]*' hb="${hlc##*/}"
  set -f  # no globbing while splitting; the callers turn it back on
  for c in $1; do
    case "$c" in fortkeep)
      # shellcheck disable=SC2254 # $var is a pattern on purpose
      case "$prev" in start|.|''|..|.config|fortkeep|$var|*[*?[\{]*) return 0 ;; esac ;;
    esac
    # shellcheck disable=SC2254 # $var is a pattern on purpose
    case "$c" in *[*?[]*|*'{'*,*'}'*|*'{'*..*'}'*|$var)  # a glob, brace or variable counts under the folder, or as ~/.config
      case "$prev" in .config|fortkeep) return 0 ;; '~'|"$hb"|'$home'|'${home}') pin_names "$c" .config && return 0 ;; esac ;;
    esac
    if [ -n "$c" ]; then lastprev="$prev"; last="$c"; fi
    prev="$c"
  done
  [ "$last" = .config ] || return 1
  # shellcheck disable=SC2254 # $var is a pattern on purpose
  case "$lastprev" in start|.|''|..|'~'|"$hb"|$var) return 0 ;; esac
  return 1
}
pin_dir() {  # TARGET — true when a cd to TARGET could land in home, ~/.config or ~/.config/fortkeep
  local t="${1%/}"
  case "$t" in ''|'~'|'$home'|'${home}'|"$hlc") return 0 ;; \~/[\$\`]*|'$home/'[\$\`]*|'${home}/'[\$\`]*) return 0 ;; esac
  # A target spelled with .., ., //, a variable, a glob or ~name could be any of them.
  case "$t" in *..*|*'$'*|*'`'*|*[*?[]*|*/./*|*/.|*//*|\~[!/]*) return 0 ;; esac
  pin_word "$t"
}
pin_check() {  # SEGMENTS — after a cd into home, ~/.config or the folder nothing writes; elsewhere no word names them
  local seg lead t w protected=0
  while IFS= read -r seg; do
    seg="${seg#"${seg%%[![:space:]]*}"}"; lead="${seg%%[[:space:]]*}"
    [ -n "$seg" ] || continue
    case "$seg" in *'${'*fortkeep*|*'${'*.config*) block "$tmsg" ;; esac
    case "$lead" in cd|pushd)
      t=""; set -f
      # shellcheck disable=SC2086 # split into words on purpose
      for w in ${seg#"$lead"}; do case "$w" in -?*) ;; *) t="$w"; break ;; esac; done
      set +f
      pin_dir "$t" && protected=1
      continue ;;
    esac
    if [ "$protected" -eq 1 ]; then
      printf '%s' "$seg" | sed -E 's#[0-9]*>[>|]?[[:space:]]*/dev/null##g; s#[0-9]*>&[0-9-]##g' | grep -q '>' && block "$tmsg"
      ro_leader "$lead" || commit_ok "$seg" || block "$tmsg"
      continue
    fi
    ro_leader "$lead" && continue
    commit_ok "$seg" && continue
    set -f
    # shellcheck disable=SC2086 # split into words on purpose
    for w in $seg; do
      w="${w##*[<>]}"
      if pin_word "$w" || pin_word "${w#*=}"; then set +f; block "$tmsg"; fi
    done
    set +f
  done <<EOF
$1
EOF
  while IFS= read -r w; do  # a redirect, even after a read-only command, can't write there either
    w="${w#>}"; w="${w#[>|]}"; w="${w#"${w%%[![:space:]]*}"}"
    [ -z "$w" ] || ! pin_word "$w" || block "$tmsg"
  done <<EOF
$(printf '%s' "$1" | grep -Eo '>[>|]?[[:space:]]*[^[:space:]<>]+')
EOF
  set +f
}
pin_check "$lsegs_j"; pin_check "$lsegs_n"
# shellcheck disable=SC2329 # called through guard_path
commit_skip() { commit_ok "$1" && return 3; return 0; }
guard_path '\.config/fortkeep' "$tmsg" commit_skip
# shellcheck disable=SC2329 # called through guard_path
rc_seg() {
  commit_ok "$1" && return 3  # a commit message may name these paths
  gitcfg_write "$1" && block "changes to the global git config go through fix scripts"
  return 0
}
guard_path "$rc" "changes to shell start-up files, LaunchAgents and agent settings go through fix scripts" rc_seg
up_re='(^|[;&|(`[:space:]/])(curl[^;&|]*[[:space:]](-T|--upload-file|-F|--form|--form-string|--json[[:space:]]+@|-d[[:space:]]*@|--data(-binary|-raw|-urlencode)?[[:space:]=]+@)|wget[^;&|]*--(post|body)-file|scp[[:space:]][^;&|]*[A-Za-z0-9_.-]+:|rsync[[:space:]][^;&|]*[A-Za-z0-9_.-]+:|s?ftp[[:space:]]|(nc|ncat|netcat)[[:space:]]|gh[[:space:]]+gist[[:space:]]+create)'
if printf '%s' "$norm" | grep -Eq "$up_re"; then
  block "uploading files from this Mac isn't allowed here"
fi
if printf '%s' "$unq" | grep -Eqi '(baseline\.sh|fortkeep[^;&|]*[[:space:]]baseline)[^;&|]*accept|baseline\.json|knockknock/baseline'; then
  block "baselines are accepted only by the person, in the Terminal app"
fi
if printf '%s' "$unq" | grep -Eqi '(private\.sh|fortkeep[^;&|]*[[:space:]]private)[^;&|]*remove'; then
  block "only the person removes a private folder: they type fortkeep private remove in the Terminal app"
fi
if printf '%s' "$unq" | grep -Eqi 'fortkeep[^;&|]*[[:space:]]uninstall'; then
  block "only the person uninstalls fortkeep, in the Terminal app"
fi
if printf '%s\n%s' "$norm" "$unq" | grep -qi '\.approvals'; then  # unq: .appr''ovals still matches
  block "approvals come only from the person's answer"
fi
if printf '%s' "$norm" | grep -Eiq '(^|[^A-Za-z0-9_.-])private-paths([^A-Za-z0-9_.-]|$)'; then
  block "private folders are managed only through checks/private.sh"
fi
exit 0
