#!/bin/bash -p
# Adds gitleaks as a global pre-commit hook, so every commit in every repo is scanned for
# secrets before it's made. Usage: apply | undo
. "$(dirname "$0")/../lib/fix.sh"
ID=BL-SE-06
fx_require_approval "$ID" "${1:-}"
. "$DEVWARD_REPO/checks/lib/shells.sh"
passes() { [ "$(/bin/bash -p "$DEVWARD_REPO/checks/macos/$ID.sh" | jq -r .status)" = PASS ]; }
g="$(devward_shell_probe zsh-login 'command -v git' | tail -n 1)"
case "$g" in /*) ;; *) g=/usr/bin/git ;; esac
changed=0
stop() {  # MESSAGE — finish as MANUAL; changes made so far are logged and can be undone
  [ "$changed" -eq 1 ] && { fx_seal "$ID"; fx_log "$ID" apply "gitleaks pre-commit hook (partly)"; }
  echo "MANUAL: $1"; exit 3
}
backup() {  # FILE — on failure, drop this run's backup folder so undo never picks a do-nothing one
  fx_backup "$ID" "$1" && return 0
  rm -rf "${DEVWARD_BACKUPS:?}/$ID/$FX_STAMP"; stop "could not back up $(devward_tilde "$1"); nothing was changed"
}
case "$1" in
  apply)
    [ -z "${GIT_CONFIG_GLOBAL:-}" ] || stop "GIT_CONFIG_GLOBAL is set, so git would write the hook to a file this fix can't back up or undo; nothing was changed. Unset it in your start-up files, open a new Terminal, then try again"
    if passes; then echo "nothing to change: gitleaks already scans every commit"; exit 0; fi
    gl="$(devward_shell_probe zsh-login 'command -v gitleaks' | tail -n 1)"
    case "$gl" in /*) ;; *) stop "install gitleaks first (brew install gitleaks), open a new Terminal, then try again" ;; esac
    # Single-quoted for the shell git runs the hook with, so a path with a space in it is still one program.
    qgl="$(printf '%s' "$gl" | jq -Rr @sh)" || stop "could not quote gitleaks' path $gl; nothing was changed"
    v="$("$g" --version 2>/dev/null | awk '{print $3}')"
    devward_version_ge "${v:-0}" 2.54 || stop "git ${v:-?} is too old for global hooks: install a newer one (brew install git), open a new Terminal, then try again"
    backup "$HOME/.gitconfig"
    backup "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
    changed=1
    { "$g" config --global hook.devward-gitleaks.event pre-commit &&
      "$g" config --global hook.devward-gitleaks.command "$qgl git --pre-commit --staged --redact --no-banner"; } \
      || stop "could not update your global git config"
    fx_seal "$ID"; fx_log "$ID" apply "gitleaks added as a global pre-commit hook"
    changed=0
    if passes; then echo "done: gitleaks now checks every commit for secrets"; exit 0; fi
    stop "the hook is set but the check still fails; run checks/run.sh --only $ID to see why" ;;
  undo)
    # Removes only the hook.devward-gitleaks section: anything else in the global git config stays.
    dir="$(fx_latest_backup "$ID")" || { echo "nothing to undo for $ID" >&2; exit 5; }
    bad=0
    # Each file apply backed up is edited by name: --global would miss the XDG file once a ~/.gitconfig exists.
    for f in "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"; do
      [ -f "$f" ] || continue
      if "$g" config --file "$f" --get-regexp '^hook\.devward-gitleaks\.' >/dev/null 2>&1; then
        "$g" config --file "$f" --remove-section hook.devward-gitleaks >/dev/null 2>&1 || bad=1
      fi
      "$g" config --file "$f" --get-regexp '^hook\.devward-gitleaks\.' >/dev/null 2>&1
      [ $? -eq 1 ] || bad=1  # 1 means gone; anything else means git couldn't read the file
    done
    fx_drop_blank_created "$dir" "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" || bad=1
    if [ "$bad" -ne 0 ]; then echo "undo incomplete: could not edit your global git config; backup kept in $(devward_tilde "$dir")" >&2; exit 6; fi
    mv "$dir/manifest.tsv" "$dir/manifest.restored.tsv"
    fx_log "$ID" undo "removed the gitleaks pre-commit hook from the global git config"
    echo "restored" ;;
esac
