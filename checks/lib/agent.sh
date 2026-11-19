#!/bin/bash
# Source it, don't run it.
# devward_agent_kind PSCMD PID — prints claude, codex or opencode when that process is one of these agents.
devward_agent_kind() {
  local comm args
  comm="$("$1" -o comm= -p "$2" 2>/dev/null)"
  case "${comm:-x}" in
    claude|*/claude|claude-code|*/claude-code|*/claude/*|*/claude-code/*) echo claude; return 0 ;;
    codex|*/codex) echo codex; return 0 ;;
    opencode|*/opencode) echo opencode; return 0 ;;
  esac
  # Installed through npm, an agent runs as node with its script, so its comm is node.
  args="$("$1" -o args= -p "$2" 2>/dev/null)"
  case "$args" in
    */@anthropic-ai/claude-code/*) echo claude ;;
    */@openai/codex/*) echo codex ;;
    */opencode-ai/*) echo opencode ;;
    *) return 1 ;;
  esac
}

# devward_agent_runs PSCMD — prints how many agents are ancestors of this shell. An npm launcher and the agent it
# starts are one agent (the same kind, parent and child); an agent that starts another through a shell makes two.
# The caller passes the ps command; no environment variable may choose it.
devward_agent_runs() {
  local ps="$1" pid=$$ n=0 kind prev="" runs=0
  while [ "$n" -lt 40 ]; do
    pid="$("$ps" -o ppid= -p "$pid" 2>/dev/null)"; pid="${pid//[[:space:]]/}"
    case "$pid" in ''|*[!0-9]*) break ;; esac
    [ "$pid" -gt 1 ] || break
    kind="$(devward_agent_kind "$ps" "$pid")" || kind=""
    [ -z "$kind" ] || [ "$kind" = "$prev" ] || runs=$((runs + 1))
    prev="$kind"
    n=$((n + 1))
  done
  echo "$runs"
}

# devward_agent_ancestor PSCMD — true when an agent (claude, codex, opencode) is a parent, grandparent, ... of this shell.
devward_agent_ancestor() { [ "$(devward_agent_runs "$1")" -gt 0 ]; }

# devward_terminal_ancestor PSCMD [HOME] — true when a terminal app or sshd is an ancestor of this shell.
# A tripwire, not a boundary: ucomm is only the executable's file name (16 characters), so a renamed or
# self-built binary still passes. Home is from the directory service; the HOME argument is for tests only.
devward_terminal_ancestor() {
  local ps="$1" pid=$$ n=0 comm ucomm home="${2:-}" app
  if [ -z "$home" ]; then
    home="$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory 2>/dev/null)"
    home="${home#NFSHomeDirectory:}"; home="${home#"${home%%[![:space:]]*}"}"  # a space in the path moves it to the next line
    [ -n "$home" ] || home=/nonexistent-home
  fi
  while [ "$n" -lt 40 ]; do
    pid="$("$ps" -o ppid= -p "$pid" 2>/dev/null)"; pid="${pid//[[:space:]]/}"
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$pid" -gt 1 ] || return 1
    comm="$("$ps" -o comm= -p "$pid" 2>/dev/null)"
    ucomm="$("$ps" -o ucomm= -p "$pid" 2>/dev/null)"; ucomm="${ucomm%"${ucomm##*[![:space:]]}"}"
    n=$((n + 1))
    case "$comm" in *:*) continue ;; esac
    # comm and ucomm are matched separately; ucomm is cut at 16 characters, so iTermServer-<version> is a prefix.
    case "$comm" in
      /System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal) [ "$ucomm" = Terminal ] && return 0 ;;
      "$home/Library/Application Support/iTerm2/iTermServer"*) case "$ucomm" in iTermServer*) return 0 ;; esac ;;
      /usr/sbin/sshd) [ "$ucomm" = sshd ] && return 0 ;;
      /usr/libexec/sshd-session) [ "$ucomm" = sshd-session ] && return 0 ;;
    esac
    # Other terminals count by path only from /Applications or ~/Applications; a renamed binary can still pass (see header).
    app="${comm#"$home"}"
    case "$app" in
      /Applications/iTerm.app/Contents/MacOS/*) [ "$ucomm" = iTerm2 ] && return 0 ;;
      /Applications/Ghostty.app/Contents/MacOS/*) [ "$ucomm" = ghostty ] && return 0 ;;
      /Applications/WezTerm.app/Contents/MacOS/*) [ "$ucomm" = wezterm-gui ] && return 0 ;;
      /Applications/kitty.app/Contents/MacOS/*) [ "$ucomm" = kitty ] && return 0 ;;
      /Applications/Alacritty.app/Contents/MacOS/*) [ "$ucomm" = alacritty ] && return 0 ;;
      /Applications/Warp.app/Contents/MacOS/*) [ "$ucomm" = stable ] && return 0 ;;
    esac
  done
  return 1
}

# devward_is_person PSCMD — true when a person started this from a terminal app or over ssh, outside any agent.
# The caller passes the ps command; no environment variable may choose it.
devward_is_person() {
  [ -z "${CLAUDECODE:-}" ] && [ -t 0 ] && [ -t 1 ] && ! devward_agent_ancestor "$1" && devward_terminal_ancestor "$1"
}

# devward_require_person PSCMD — exits 4 unless devward_is_person.
devward_require_person() {
  if ! devward_is_person "$1"; then
    echo "refused: run this yourself in a terminal app (Terminal, iTerm2, Ghostty, WezTerm, kitty, Alacritty or Warp) or over ssh, not through an agent" >&2
    exit 4
  fi
}
