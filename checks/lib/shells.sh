#!/bin/bash
# Runs a snippet in the person's real shells, the way scripts, IDEs and agents start them.
# The shells read the person's start-up files, so every probe has a timeout and no stdin.
DEVWARD_SHELL_TIMEOUT="${DEVWARD_SHELL_TIMEOUT:-10}"

devward_shell_types() {  # the shell types that count on this Mac, one per line
  printf '%s\n' zsh-login zsh clean-zsh-login zsh-interactive
  if [ -f "$HOME/.bashrc" ] || [ -f "$HOME/.bash_profile" ] || [ -f "$HOME/.profile" ]; then
    printf '%s\n' bash-login bash
  fi
}

devward_shell_probe() {  # TYPE SNIPPET — prints the snippet's stdout; 142 = timed out
  local t="$DEVWARD_SHELL_TIMEOUT" clean mine
  clean=(/usr/bin/env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-${USER:-}}" TERM=dumb)
  mine=(/usr/bin/env PATH="$DEVWARD_USER_PATH")  # the shells inherit the person's PATH, not the one devward runs with
  case "$1" in
    zsh-login) devward_timeout "$t" "${mine[@]}" /bin/zsh -lc "$2" ;;
    zsh) devward_timeout "$t" "${mine[@]}" /bin/zsh -c "$2" ;;
    clean-zsh-login) devward_timeout "$t" "${clean[@]}" /bin/zsh -lc "$2" ;;
    bash-login) devward_timeout "$t" "${clean[@]}" /bin/bash -lc "$2" ;;
    bash) devward_timeout "$t" "${mine[@]}" /bin/zsh -c 'exec /bin/bash -c "$1"' zsh "$2" ;;
    # Inside $( ) an interactive zsh can print nothing without a TERM; stdin from /dev/null keeps it off the terminal.
    zsh-interactive) devward_timeout "$t" "${mine[@]}" DISABLE_AUTO_UPDATE=true TERM=dumb /bin/zsh -ic "$2" ;;
    *) return 2 ;;
  esac </dev/null 2>/dev/null
}

devward_shell_label() {
  case "$1" in
    zsh-login) echo "zsh -lc" ;; zsh) echo "zsh -c" ;; clean-zsh-login) echo "env -i zsh -lc" ;;
    bash-login) echo "bash -lc" ;; bash) echo "bash -c" ;; zsh-interactive) echo "interactive zsh" ;;
    *) echo "$1" ;;
  esac
}
