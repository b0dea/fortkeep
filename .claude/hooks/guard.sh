#!/bin/bash
# PreToolUse for every tool: Claude Code runs it for all of them, Codex for every local tool (not its hosted web search,
# which .codex/config.toml turns off, nor write_stdin, which feeds a command already checked), the OpenCode plugin
# for the tools it maps. A person's session (not fortkeep_dev_session) is allow-listed: the shell runs only fortkeep's own
# scripts (allow-list), reads stay in this checkout and the agent's own folders, writes only in those folders, and
# any other tool is refused unless it touches no file and runs no command. A development session keeps the
# deny-list guards: bash-guard.sh, private-guard.sh and write-guard.sh.
set -o pipefail
# shellcheck source=.claude/hooks/lib.sh
. "$(dirname "$0")/lib.sh"
fail_closed
input="$(cat)"
[ -n "$input" ] || block "guard could not read the request"
tool="$(jq -r '.tool_name // "" | strings' <<<"$input")" || block "guard could not read the request"
[ -n "$tool" ] || block "guard could not read the request"
also() { local s; for s in "$@"; do "$HOOKS/$s.sh" <<<"$input" || exit "$?"; done; }  # SCRIPT... — run these guards too

# In either session: before the question is shown, only the model can have written its answers, and the approval
# recorder mints a token from the answers it gets back.
if [ "$tool" = AskUserQuestion ]; then
  jq -e '.tool_input | has("answers") | not' >/dev/null <<<"$input" \
    || block "a question is asked without answers filled in: only the person answers it"
fi
# A shell call names its command once: with both command (Claude Code) and cmd (Codex's own name), the guards would
# check one while the agent might run the other.
if [ "$tool" = Bash ]; then
  jq -e '.tool_input | has("command") and has("cmd") | not' >/dev/null <<<"$input" \
    || block "a shell call names its command once, as command or cmd, not both"
fi

if fortkeep_dev_session; then
  case "$tool" in
    Bash) also bash-guard private-guard ;;
    Read|Grep|Glob) also private-guard ;;
    Edit|Write|MultiEdit|NotebookEdit|apply_patch) also write-guard private-guard ;;
  esac
  exit 0
fi

cwd="$(jq -r '.cwd // empty' <<<"$input")" || block "guard could not read the request"
repo="$(real "$REPO")" || block "guard could not find this repo"

arg_ok() {  # KIND WORD — true when WORD is a value of that kind (allow-list)
  local re
  case "$1" in
    ID) re='^(BL|GD|OV)-[A-Z]{2,4}-[0-9]{2}$'; [[ $2 =~ $re ]] ;;
    FIX) arg_ok ID "$2" && [ -f "$REPO/fixes/macos/$2.sh" ] ;;
    OVERLAYS) re='^[a-z0-9, -]{0,200}$'; [[ $2 =~ $re ]] ;;
    FOLDER)
      # shellcheck disable=SC2088 # a literal ~/: checks/private.sh expands it itself
      case "$2" in /*|'~/'*) [ "${#2}" -le 1024 ] ;; *) return 1 ;; esac ;;
    TEXT) [ -n "$2" ] && [ "${#2}" -le 300 ] ;;
    FILE) re='^[A-Za-z0-9_.][A-Za-z0-9_./-]*$'; [[ $2 =~ $re ]] || return 1
      case "/$2/" in */../*) return 1 ;; esac
      (read_ok "$REPO/$2" file) ;;  # a subshell: a refusal here only fails this match
    *) return 1 ;;
  esac
}

allowed_cmd() {  # true when the words in W match one line of the allow-list, word for word
  local line pat i ok
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    set -f
    # shellcheck disable=SC2086 # split into words on purpose
    set -- $line
    set +f
    [ "$#" -eq "${#W[@]}" ] || continue
    ascii "${W[0]}" || continue
    case "$1" in
      *FIX*) case "${W[0]}" in "${1%%FIX*}"*"${1#*FIX}") ;; *) continue ;; esac
        i="${W[0]#"${1%%FIX*}"}"; arg_ok FIX "${i%"${1#*FIX}"}" || continue ;;
      *) [ "${W[0]}" = "$1" ] && [ -f "$REPO/$1" ] || continue ;;
    esac
    shift; i=1; ok=1
    for pat in "$@"; do
      # Only a free text (a name or a reason) may hold letters beyond ASCII.
      [ "$pat" = TEXT ] || ascii "${W[$i]}" || ok=0
      case "$pat" in
        ID|FIX|OVERLAYS|FOLDER|TEXT|FILE) arg_ok "$pat" "${W[$i]}" || ok=0 ;;
        *) case "${W[$i]}" in ''|*'|'*) ok=0 ;; esac
          case "|$pat|" in *"|${W[$i]}|"*) ;; *) ok=0 ;; esac ;;
      esac
      i=$((i + 1))
    done
    [ "$ok" -eq 1 ] && return 0
  done < "$HOOKS/allow-list"
  return 1
}

shell() {
  local cmd out w x mode
  # Codex may send the command as a list of words: bash -lc SCRIPT is checked as SCRIPT, plain words are joined.
  cmd="$(jq -j '.tool_input.command // .tool_input.cmd // "" | if type == "string" then .
    elif type == "array" and all(.[]; type == "string") then
      (if length == 3 and (.[0] | test("^(/bin/|/usr/bin/)?(ba|z)?sh$")) and (.[1] | test("^-l?c$")) then .[2]
       elif all(.[]; test("^[A-Za-z0-9_./,:+-]+$")) then join(" ") else error("unsafe words") end)
    else error("no command") end' <<<"$input"; printf x)" || block "guard could not read the command"
  cmd="${cmd%x}"
  [ -n "$cmd" ] || block "guard could not read the command"
  [ -n "$cwd" ] || block "guard could not read the working folder"
  for w in "$cwd" "$(jq -r '.tool_input.workdir // empty' <<<"$input")"; do
    [ -n "$w" ] || continue
    [ "$(real "$w")" = "$repo" ] || block "run fortkeep's scripts from this repo's folder, $REPO, not from another folder"
  done
  if printf '%s' "$cmd" | grep -Eq '(^|[^A-Za-z0-9_.-])sudo([^A-Za-z0-9_.-]|$)'; then
    block "The agent never runs sudo. Give the person the exact command to type in the Terminal app, not in this chat."
  fi
  out="$(printf '%s' "$cmd" | perl "$HOOKS/shell-words.pl" 2>&1)" || block "$out"
  W=()
  while IFS= read -r x; do W[${#W[@]}]="${x#w:}"; done <<<"$out"
  if allowed_cmd; then
    case "${W[0]}" in fixes/macos/*)
      mode="$(jq -r '.permission_mode // empty' <<<"$input")"
      case "$mode" in bypassPermissions|acceptEdits|auto)
        block "fixes don't run while the agent is in $mode mode: the person's own prompt before the change would be skipped. Ask them to switch back to the default mode (shift+tab in Claude Code), then ask again." ;;
      esac ;;
    esac
    return 0
  fi
  case "${W[0]}" in
    checks/baseline.sh) block "only the person accepts a baseline: they type checks/baseline.sh accept in the Terminal app" ;;
    checks/update.sh) block "the person updates fortkeep: they type fortkeep update in the Terminal app" ;;
    checks/private.sh)
      [ "${W[1]:-}" != remove ] || block "only the person removes a private folder: they type fortkeep private remove \"<path>\" in the Terminal app"
      [ "${W[1]:-}" != add ] || ascii "${W[2]:-}" || block "a folder name with letters beyond ASCII can't be added from here: the person types fortkeep private add \"<path>\" in the Terminal app" ;;
    cat|head|tail|less|more|sed|awk|jq|grep|egrep|rg|ls|find|file|stat|wc|open)
      block "read files with your read tools, not the shell (in Codex, which has none: checks/show.sh <path>)" ;;
  esac
  block "in a person's session the agent runs only fortkeep's own scripts, one per command, from this repo's folder and spelled as the skills write them (the list is .claude/hooks/allow-list)"
}

no_braces() {  # TEXT — the check cuts a pattern at its first glob character, so a brace alternative ({/elsewhere,x})
  # would go unchecked
  case "$1" in *[{}]*) block "a pattern or folder with braces ({a,b}) is refused in a person's session: search each one on its own" ;; esac
}

search() {  # Grep and Glob: the folder they search
  local p base pat
  case "$tool" in
    Grep)
      p="$(jq -r '.tool_input.path // empty' <<<"$input")"
      [ -n "$p" ] || p="${cwd:-$REPO}"
      ascii "$p" || block "non-ASCII characters are refused in a person's session"
      no_braces "$(jq -r '.tool_input.glob // empty | tostring' <<<"$input")"
      if [ -f "$(printf '%s\n' "$p" | CWD="${cwd:-$REPO}" perl "$HOOKS/resolve-paths.pl" exact)" ]; then read_ok "$p" file; else read_ok "$p" root; fi ;;
    Glob)
      pat="$(jq -r '.tool_input.pattern // ""' <<<"$input")"; p="$(jq -r '.tool_input.path // empty' <<<"$input")"
      ascii "$pat$p" || block "non-ASCII characters are refused in a person's session"
      no_braces "$pat$p"
      case "$pat" in *..*) block "a pattern may not climb out of its folder" ;; esac
      base="$(printf '%s\n' "${p:-${cwd:-$REPO}}" | CWD="${cwd:-$REPO}" perl "$HOOKS/resolve-paths.pl" exact)"
      read_ok "$(printf '%s\n' "$pat" | CWD="$base" perl "$HOOKS/resolve-paths.pl" lines)" root ;;
  esac
}

artifact() {  # the Artifact tool uploads local files: each one it names must be one the read tools may read
  local p
  jq -e '(.tool_input.root // .tool_input.out_dir // null) == null' >/dev/null <<<"$input" \
    || block "the Artifact tool takes no root or out_dir in a person's session"
  while IFS= read -r p; do
    [ -z "$p" ] || read_ok "$p" file
  done <<EOF
$(jq -r '.tool_input | [.file_path, (.file_paths // [])[],
  ((.files // {}) | if type == "array" then .[].path elif type == "object" then (.[] | if type == "string" then .
    elif type == "object" then .from else empty end) else empty end)] | .[] | strings' <<<"$input")
EOF
}

case "$tool" in
  # The tools that touch no file and run no command: the question, todo and skill tools, plan mode, and Claude Code's
  # loader for deferred tools; Codex's plan, question and the tool that feeds a running command's input. The OpenCode
  # plugin keeps the same set (its UNGUARDED).
  AskUserQuestion|TodoWrite|TaskCreate|TaskUpdate|TaskList|TaskGet|Skill|ToolSearch) exit 0 ;;
  EnterPlanMode|ExitPlanMode|update_plan|request_user_input|write_stdin) exit 0 ;;
  # No skill needs the web, and a fetched URL or a search query can carry what the agent read (results, scans, the
  # change log) off this Mac.
  WebFetch|WebSearch|web_search)
    block "the agent doesn't use the web in a person's session: a link or a search could carry this Mac's results off it. If something needs looking up, the person can do it in their browser." ;;
  Artifact) artifact; also private-guard ;;
  Bash) shell ;;
  Read)
    read_ok "$(jq -r '.tool_input.file_path // .tool_input.path // ""' <<<"$input")" file
    also private-guard ;;
  Grep|Glob) search; also private-guard ;;
  Edit|Write|MultiEdit|NotebookEdit|apply_patch) also write-guard private-guard ;;
  *) block "the $tool tool has no guard in a person's session, so it is refused" ;;
esac
exit 0
