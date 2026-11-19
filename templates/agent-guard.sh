#!/bin/bash
# Pre-command guard for AI coding agents (Claude Code PreToolUse on Bash and Write|Edit|MultiEdit; Codex on Bash and
# apply_patch).
# Refuses the usual ways around Safe Chain and edits to the files that enforce it. Exit 2 = refuse.
# Pattern matching, not a sandbox: it stops an agent that slips or is talked into it, not globs or names built from pieces.
PATH=/usr/bin:/bin  # the guard's own tools, never a lookalike earlier on the agent's PATH
refuse() { echo "Refused by agent-guard: $1" >&2; exit 2; }
input="$(cat)" || refuse "could not read the request"
case "$input" in *[![:space:]]*) ;; *) refuse "empty request" ;; esac
J=/usr/bin/jq; [ -x "$J" ] || J="$(command -v jq)" || refuse "jq is missing"
tool="$(printf '%s' "$input" | "$J" -r '.tool_name // ""' 2>/dev/null)" || refuse "could not read the request"
dend='([/[:space:];&|)*?]|\[|$)'  # a folder name ends here: slash, separator, glob or end
protected='\.zshrc|\.zprofile|\.zshenv|\.zlogin|\.bashrc|\.bash_profile|/\.profile|/\.claude/settings[^/]*\.json|\.claude\.json|managed-settings|agent-guard|/LaunchAgents'"$dend"'|/\.safe-chain'"$dend"'|/\.codex'"$dend"'|/\.config/devward'"$dend"'|/plugins/cache'"$dend"'|/plugins/installed_plugins\.json'
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
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
plugin_run() {  # FIRST REST — a script in a Claude plugins cache, run directly or by a shell, naming nothing else protected
  local s="$1" r="$2"
  case "$s" in bash|sh|zsh|/bin/bash|/bin/sh|/bin/zsh) r="${r#"${r%%[![:space:]]*}"}"; s="${r%%[[:space:]]*}"; r="${r#"$s"}" ;; esac
  # A plain path only (from /, ~/ or a double-quoted $HOME/): no other expansion, assignment or glob,
  # and nothing protected before the cache.
  # shellcheck disable=SC2016 # a literal $HOME in the command text
  printf '%s' "$s" | grep -Eq '^(~/|/|\$HOME/|\$\{HOME\}/)[A-Za-z0-9._/@+-]*/plugins/cache/[A-Za-z0-9._/@+-]+$' || return 1
  case "$s" in '$'*) home_plain || return 1; case "$craw" in *"\"$s"*) ;; *) return 1 ;; esac ;; esac
  case "$s" in *..*) return 1 ;; esac
  printf '%s' "${s%%/plugins/cache/*}" | grep -Eiq "$protected" && return 1
  case "$r" in *[{}]*) return 1 ;; esac
  ! printf '%s' "$r" | grep -Eiq "$protected"
}
home_plain() {  # true when HOME appears only as $HOME/ or ${HOME}/, so nothing in the command can change it
  local t="${c3//\$HOME\//}"
  t="${t//\$\{HOME\}\//}"
  case "$t" in *HOME*) return 1 ;; esac
}
plain_words() {  # WORD… — none could expand into an option: no braces, glob start, ~ but ~/, or $ but $HOME/
  local x
  home_plain || return 1
  case "$c3" in *IFS*) return 1 ;; esac
  for x in "$@"; do
    case "$x" in -s|--) continue ;; *[{}]*|[*?[]*) return 1 ;; \~/*) ;; \~*) return 1 ;; esac
    x="${x#\$HOME/}"; case "$x" in -*|*'$'*|*'`'*) return 1 ;; esac
  done
  return 0
}
# Exit 0 when a separator sits inside quotes, $'…' or ${…} or after a backslash, or a control byte appears:
# the shell reads such a separator as text, but the segments below would split there. Fail closed only.
# shellcheck disable=SC2016 # an awk program, not shell
qsep='BEGIN { s = ENVIRON["DEVWARD_QS"]; n = length(s); q = ""; d = 0; st = ""; sep = ";&|()`\n"
  if (s ~ /[\001-\010\013-\037\177]/) exit 0
  for (i = 1; i <= n; i++) { ch = substr(s, i, 1)
    if (q == "" && st != "") {
      if (index(sep, ch) || ch == "\047" || ch == "\"" || ch == "\\") exit 0
      if (ch == substr(st, length(st), 1)) { st = substr(st, 1, length(st) - 1); continue }
      if (ch == "$" && (substr(s, i + 1, 1) == "{" || substr(s, i + 1, 1) == "[")) { st = st (substr(s, i + 1, 1) == "{" ? "}" : "]"); i++ }
      continue }
    if (q == "\047") { if (ch == "\047") q = ""; else if (index(sep, ch)) exit 0; continue }
    if (q == "$") { if (ch == "\\") { if (index(sep, substr(s, i + 1, 1))) exit 0; i++ }
      else if (ch == "\047") q = ""; else if (index(sep, ch)) exit 0; continue }
    if (ch == "\\") { nx = substr(s, i + 1, 1); if (nx != "\n" && nx != "" && index(sep, nx)) exit 0; i++; continue }
    if (q == "\"") {
      if (ch == "$" && substr(s, i + 1, 1) == "{") { d++; i++; continue }
      if (d > 0 && ch == "}") { d--; continue }
      if (d > 0 && (ch == "\"" || ch == "\047")) exit 0
      if (ch == "\"") q = ""; else if (index(sep, ch)) exit 0; continue }
    if (ch == "$" && substr(s, i + 1, 1) == "$") { i++; continue }
    if (ch == "$" && substr(s, i + 1, 1) == "\047") { q = "$"; i++; continue }
    if (ch == "$" && (substr(s, i + 1, 1) == "{" || substr(s, i + 1, 1) == "[")) { st = (substr(s, i + 1, 1) == "{" ? "}" : "]"); i++; continue }
    if (ch == "\047" || ch == "\"") q = ch }
  exit 1 }'
ro_plutil() {  # REST — plutil -p or -lint, with no other option than -s
  local x
  set -f
  # shellcheck disable=SC2086 # split into words on purpose
  set -- $1
  set +f
  case "${1:-}" in -p|-lint) shift ;; *) return 1 ;; esac
  for x in "$@"; do case "$x" in -s|--) ;; -*) return 1 ;; esac; done
  plain_words "$@"
}
ro_sed() {  # REST — sed -n whose script only prints: p after an optional line, /re/ or a range of them
  local x a='([0-9]+|/[^/]*/)'
  set -f
  # shellcheck disable=SC2086 # split into words on purpose
  set -- $1
  set +f
  [ "${1:-}" = -n ] || return 1
  case "${2:-}" in *'$'*|*'`'*) return 1 ;; esac
  printf '%s' "${2:-}" | grep -Eq "^($a(,$a)?)?p\$" || return 1
  shift 2
  for x in "$@"; do case "$x" in -*) return 1 ;; esac; done
  plain_words "$@"
}
check_edit() {  # FILE — refuses an edit to FILE when it, or what its symlinks lead to, is a protected file
  local f="$1" r="$1" n=0 t d cc p k
  # Follow a symlink to its target (at most 40 hops) and compare without letter case, like macOS does.
  while [ -L "$r" ] && [ "$n" -lt 40 ]; do
    t="$(readlink "$r")" || break
    case "$t" in /*) r="$t" ;; *) r="$(dirname "$r")/$t" ;; esac; n=$((n + 1))
  done
  d="$(dirname "$r")"; [ -d "$d" ] && r="$(cd "$d" && pwd -P)/$(basename "$r")"
  cc=""; [ -n "${CLAUDE_CONFIG_DIR:-}" ] && cc="$(lower "$CLAUDE_CONFIG_DIR")"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && [ -d "$CLAUDE_CONFIG_DIR" ] && cc="$cc"$'\n'"$(lower "$(cd "$CLAUDE_CONFIG_DIR" && pwd -P)")"
  for p in "$f" "$r"; do
    printf '%s' "$p" | grep -Eiq "($protected)" && refuse "editing the files that enforce these rules"
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      case "$(lower "$p")" in "$k"/settings*.json|"$k"/plugins/*) refuse "editing the files that enforce these rules" ;; esac
    done <<EOF
$cc
EOF
  done
}
case "$tool" in
  Bash)
    c="$(printf '%s' "$input" | "$J" -r '.tool_input.command // ""')" || refuse "could not read the request"
    [ "${#c}" -le 65536 ] || refuse "command too long to check in time; write long content with the Write tool"
    craw="$c"; c="${c//$'\n'/ }"
    b='(^|[;&|(`[:space:]])'
    pm='(npm|npx|pnpm|pnpx|yarn|bun|bunx|pip|pip3|pipx|uv|uvx|poetry|pdm)'
    cr="${craw//>|/>}"  # >| is one redirect, not a pipe: never split there
    c2="$(printf '%s' "$cr" | tr -d "\"'\\\\" | sed -E 's#[^[:space:];&|]*/\.safe-chain/shims/([A-Za-z0-9_-]+)([[:space:];&|]|$)#\1\2#g')"
    c3="$(printf '%s' "$cr" | tr -d "\"'\\\\")"  # quotes and backslashes removed, shim paths kept
    # shellcheck disable=SC2020 # six separators, one newline each
    # Every word is checked, except in a segment led by a command that only looks at paths.
    while IFS= read -r seg; do
      seg="${seg#"${seg%%[![:space:]]*}"}"
      case "${seg%%[[:space:]]*}" in ls|cd|du|rm|rmdir|mkdir|cat|stat|file|tree|open|readlink|realpath) continue ;; esac
      printf '%s' "$seg" | grep -Eq '(^|[[:space:]])[^[:space:]]*/'"$pm"'([[:space:]]|$)' && refuse "a package manager by full path skips Safe Chain"
      printf '%s' "$seg" | grep -Eq '(^|[[:space:]])[^[:space:]]*/python[0-9.]*[[:space:]]+-m[[:space:]]+pip' && refuse "pip through a full python path skips Safe Chain"
    done <<EOF
$(printf '%s' "$c2" | tr ';&|()`' '\n\n\n\n\n\n')
EOF
    printf '%s' "$c" | grep -Eq "$b"'(PATH=|([^[:space:];&|]*/)?env[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(-i|PATH=|(--ignore-environment|-|-u[[:space:]]*PATH|--unset[=[:space:]]PATH)([[:space:]]|$)))' && refuse "rewriting PATH or clearing the environment skips Safe Chain"
    printf '%s' "$c" | grep -Eq '(SAFE_CHAIN_[A-Z_]*=|--safe-chain-|safe-chain[[:space:]]+uninstall)' && refuse "changing Safe Chain's settings is for the person, not the agent"
    printf '%s' "$c3" | grep -Eq "$b"'unset[[:space:]][^;&|]*SAFE_CHAIN_|(^|[[:space:]])(-u[[:space:]]*|--unset[=[:space:]][[:space:]]*)SAFE_CHAIN_' && refuse "changing Safe Chain's settings is for the person, not the agent"
    printf '%s' "$c" | grep -Eiq '(npm_config_[^=[:space:]]*registry|yarn_npm_registry_server|bun_config_registry|pip_index_url|pip_extra_index_url|uv_index_url|uv_extra_index_url|uv_default_index)=' && refuse "registry override"
    printf '%s' "$c" | grep -Eq "$b$pm"'[[:space:]][^;&|]*(--[^[:space:]=]*registry|--index-url|--extra-index-url|--default-index|[[:space:]]-i[[:space:]]+https?:)' && refuse "registry override"
    printf '%s' "$c" | grep -Eq "$b"'(npm|pnpm|yarn)[[:space:]]+config[[:space:]]+set[[:space:]]+[^;&|]*registry' && refuse "registry override"
    printf '%s' "$c2" | grep -Eq "$b"'([^[:space:];&|]*/)?node[[:space:]][^;&|]*(^|[/[:space:]])(npm-cli|npx-cli|pnpm|pnpx|yarn)\.c?js([[:space:]]|$)' && refuse "a package manager's own script run with node skips Safe Chain"
    printf '%s' "$c2" | grep -Eq "$b"'([^[:space:];&|]*/)?corepack[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(npm|npx|pnpm|pnpx|yarn)(@[^[:space:]]*)?([[:space:]]|$)' && refuse "corepack runs the package manager past Safe Chain"
    printf '%s' "$c" | grep -Eq '(curl|wget).*\|[[:space:]]*(sudo[[:space:]]+(-[^[:space:]]+[[:space:]]+)*)?(env[[:space:]]+)?([^[:space:]]*/)?(ba|z|da|k)?sh([[:space:]]|$)' && refuse "piping a download into a shell"
    printf '%s' "$c" | grep -Eq "$b"'(([^[:space:]]*/)?(ba|z|da|k)?sh|source|eval|\.)[[:space:]]+(-[^[:space:]]+[[:space:]]+)*["'"'"']?(<[[:space:]]*)?(<\(|\$\(|[`])[[:space:]]*([^[:space:]]*/)?(curl|wget)' && refuse "running a download as a script"
    printf '%s' "$c" | grep -Eiq "$b"'node[[:space:]]+[^;&|[:space:]]*\.(woff2?|ttf|otf|eot|png|jpe?g|gif|ico|svg|dict)([[:space:]]|$)' && refuse "running a font or image file as code"
    # Commands whose purpose is to print a secret: varlock's printers and unredacted output, Keychain's password readers.
    sv="prints secret values into the agent's context; run it yourself in the Terminal app if you need to see a value"
    printf '%s' "$c3" | grep -Eq '_VARLOCK_REDACT_STDOUT=' && refuse "$sv"
    vl='(^|[[:space:]])([^[:space:]]*/)?varlock[[:space:]]+'
    # shellcheck disable=SC2020 # six separators, one newline each
    while IFS= read -r seg; do
      if printf '%s' "$seg" | grep -Eiq "$vl"; then
        printf '%s' "$seg" | grep -Eiq "$vl"'(printenv|reveal)([[:space:]]|$)' && refuse "$sv"
        printf '%s' "$seg" | grep -Eiq "$vl"'.*--no-redact-stdout([=[:space:]]|$)' && refuse "$sv"
        # load prints values in these formats; --agent redacts them.
        printf '%s' "$seg" | grep -Eiq "$vl"'load([[:space:]].*)?[[:space:]](--format|-f)([=[:space:]][[:space:]]*)?(env|shell|json|json-full)([[:space:]]|$)' \
          && ! printf '%s' "$seg" | grep -Eq '(^|[[:space:]])--agent([[:space:]]|$)' && refuse "$sv"
      fi
      # -g and -w are the only find-*-password options without a value, so a word starting with either asks for the password.
      printf '%s' "$seg" | grep -Eiq '(^|[[:space:]])([^[:space:]]*/)?security[[:space:]](.*[[:space:]])?find-(generic|internet)-password([[:space:]]|$)' \
        && printf '%s' "$seg" | grep -Eq '[[:space:]]-[gw]' && refuse "$sv"
    done <<EOF
$(printf '%s' "$c3" | tr ';&|()`' '\n\n\n\n\n\n')
EOF
    # Protected files: no redirect into one, and a segment naming one must start with a read-only command.
    printf '%s' "$c3" | grep -Eiq "(>|<>)[>&|!]*[[:space:]]*[^[:space:];&|]*($protected)" && refuse "editing the files that enforce these rules"
    printf '%s' "$c3" | grep -Eiq "$protected" && DEVWARD_QS="$craw" LC_ALL=C awk "$qsep" && refuse "a quoted or escaped separator beside a protected path"
    # xargs or a substitution could hand a protected path to any command (direct shim runs don't count).
    printf '%s' "$c2" | grep -Eiq "$protected" && printf '%s' "$c2" | grep -Eq '(^|[^A-Za-z0-9_])xargs([^A-Za-z0-9_]|$)|\$\(|`' && refuse "editing the files that enforce these rules"
    # shellcheck disable=SC2020 # six separators, one newline each
    while IFS= read -r seg; do
      seg="${seg#"${seg%%[![:space:]]*}"}"
      printf '%s' "$seg" | grep -Eiq "$protected" || continue
      w="${seg%%[[:space:]]*}"; rest="${seg#"$w"}"
      case "$w" in */.safe-chain/shims/*/*|*..*) ;; */.safe-chain/shims/*) printf '%s' "$rest" | grep -Eiq "$protected" || continue ;; esac
      plugin_run "$w" "$rest" && continue
      case "$w" in
        cat|head|tail|less|more|grep|egrep|fgrep|rg|diff|cmp|ls|stat|file|wc|shasum|md5|readlink|realpath|du|test|\[|echo|printf|source|.|jq) continue ;;
        plutil) ro_plutil "$rest" && continue ;;
        sed) case "$craw" in *\\*) ;; *) ro_sed "$rest" && continue ;; esac ;;  # sed judged without backslashes could hide a w
        cp) case " $seg " in *" -t"*|*" --target-directory"*) ;; *) dst="$(cp_dest "$seg")"; case "$dst" in -*|'') ;; *) printf '%s' "$dst" | grep -Eiq "$protected" || continue ;; esac ;; esac ;;
      esac
      refuse "editing the files that enforce these rules"
    done <<EOF
$(printf '%s' "$c3" | tr ';&|()`' '\n\n\n\n\n\n')
EOF
    ;;
  Write|Edit|MultiEdit|NotebookEdit)
    f="$(printf '%s' "$input" | "$J" -r '.tool_input.file_path // .tool_input.notebook_path // ""')" || refuse "could not read the request"
    check_edit "$f"
    ;;
  apply_patch)
    # Codex's file edits: the patch is the command. Every file it names, a move's destination included, is checked
    # like a single edit, relative to the request's folder. Codex trims each line of any Unicode space before reading
    # a header, so this does too; a line that starts like a header (*** and a word) but isn't one it knows is refused.
    p="$(printf '%s' "$input" | "$J" -r '.tool_input.command // "" | strings')" || refuse "could not read the request"
    w="$(printf '%s' "$input" | "$J" -r '.cwd // ""')" || refuse "could not read the request"
    files="$(printf '%s\n' "$p" | perl -CSD -ne '
      s/^[\p{Space}\x{FEFF}]+|[\p{Space}\x{FEFF}]+$//g;
      next unless /^\*\*\*\s*\p{L}/;
      if (/^\*\*\*\s*(?:Add|Update|Delete)\s+File\s*:\s*(.+)$/ || /^\*\*\*\s*Move\s+to\s*:\s*(.+)$/) { print "$1\n"; next }
      next if /^\*\*\*\s*(?:Begin Patch|End Patch|End of File)$/;
      exit 1')" || refuse "could not read the patch"
    [ -n "$files" ] || refuse "could not read the patch"
    while IFS= read -r f; do
      case "$f" in /*) ;; *) [ -n "$w" ] && f="$w/$f" ;; esac
      check_edit "$f"
    done <<EOF
$files
EOF
    ;;
esac
exit 0
