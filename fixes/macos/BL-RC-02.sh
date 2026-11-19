#!/bin/bash -p
# Installs the git scan hook, which checks the files a clone, pull or checkout brings in, as a
# global git hook for post-checkout, post-merge and post-rewrite. Usage: apply | undo
. "$(dirname "$0")/../lib/fix.sh"
ID=BL-RC-02
fx_require_approval "$ID" "${1:-}"
. "$DEVWARD_REPO/checks/lib/shells.sh"
DEST="$HOME/.local/bin/git-scan-new-files"
passes() { [ "$(/bin/bash -p "$DEVWARD_REPO/checks/macos/$ID.sh" | jq -r .status)" = PASS ]; }
changed=0
stop() {  # MESSAGE — finish as MANUAL; changes made so far are logged and can be undone
  [ "$changed" -eq 1 ] && { fx_seal "$ID"; fx_log "$ID" apply "git scan hook installed (partly)"; }
  echo "MANUAL: $1"; exit 3
}
backup() {  # FILE — on failure, drop this run's backup folder so undo never picks a do-nothing one
  fx_backup "$ID" "$1" && return 0
  rm -rf "${DEVWARD_BACKUPS:?}/$ID/$FX_STAMP"; stop "could not back up $(devward_tilde "$1"); nothing was changed"
}
case "$1" in
  apply)
    [ -z "${GIT_CONFIG_GLOBAL:-}" ] || stop "GIT_CONFIG_GLOBAL is set, so git would write the hooks to a file this fix can't back up or undo; nothing was changed. Unset it in your start-up files, open a new Terminal, then try again"
    if passes; then echo "nothing to change: a scan hook already runs after checkout, merge and rewrite"; exit 0; fi
    g="$(devward_shell_probe zsh-login 'command -v git' | tail -n 1)"
    case "$g" in /*) ;; *) g=/usr/bin/git ;; esac
    v="$("$g" --version 2>/dev/null | awk '{print $3}')"
    devward_version_ge "${v:-0}" 2.54 || stop "git ${v:-?} is too old for global hooks: install a newer one (brew install git), open a new Terminal, then try again"
    { xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; } || stop "the scan needs Apple's Command Line Tools: run xcode-select --install, then try again"
    mkdir -p "$(dirname "$DEST")" || stop "could not create $(devward_tilde "$(dirname "$DEST")")"
    backup "$DEST"
    backup "$HOME/.gitconfig"
    backup "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"
    changed=1
    { cp "$DEVWARD_REPO/fixes/files/git-scan-new-files" "$DEST" && chmod 755 "$DEST"; } || stop "could not write $(devward_tilde "$DEST")"
    # Quoted and spelled with $HOME, which the shell git runs the hook with expands: a home folder with a space in
    # it still names one program, and the BL-RC-02 check reads the same spelling.
    for ev in post-checkout post-merge post-rewrite; do
      n="devward-scan-${ev#post-}"
      # shellcheck disable=SC2016 # $HOME is for the hook's shell to expand
      { "$g" config --global "hook.$n.event" "$ev" && "$g" config --global "hook.$n.command" "\"\$HOME/${DEST#"$HOME"/}\" $ev"; } \
        || stop "could not update your global git config"
    done
    fx_seal "$ID"; fx_log "$ID" apply "git scan hook installed for checkout, merge and rewrite"
    changed=0
    if passes; then echo "done: every clone, pull and checkout is now scanned"; exit 0; fi
    stop "the hook is installed but the check still fails; run checks/run.sh --only $ID to see why" ;;
  undo)
    # Removes only what apply added: its hook.devward-scan-* sections, then the scanner if it's still as
    # apply left it. Anything else in the global git config stays. A failure stops before the scanner.
    dir="$(fx_latest_backup "$ID")" || { echo "nothing to undo for $ID" >&2; exit 5; }
    g="$(devward_shell_probe zsh-login 'command -v git' | tail -n 1)"
    case "$g" in /*) ;; *) g=/usr/bin/git ;; esac
    bad=0; kept=""
    # Each file apply backed up is edited by name: --global would miss the XDG file once a ~/.gitconfig exists.
    for f in "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config"; do
      [ -f "$f" ] || continue
      for ev in checkout merge rewrite; do
        if "$g" config --file "$f" --get-regexp "^hook\.devward-scan-$ev\." >/dev/null 2>&1; then
          "$g" config --file "$f" --remove-section "hook.devward-scan-$ev" >/dev/null 2>&1 || bad=1
        fi
        "$g" config --file "$f" --get-regexp "^hook\.devward-scan-$ev\." >/dev/null 2>&1
        [ $? -eq 1 ] || bad=1  # 1 means gone; anything else means git couldn't read the file
      done
    done
    fx_drop_blank_created "$dir" "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" || bad=1
    if [ "$bad" -eq 0 ]; then
      if fx_unchanged "$dir" "$DEST"; then fx_restore_file "$dir" "$DEST" || bad=1; else kept="$(devward_tilde "$DEST")"; fi
    fi
    if [ "$bad" -ne 0 ]; then echo "undo incomplete; backup kept in $(devward_tilde "$dir")" >&2; exit 6; fi
    mv "$dir/manifest.tsv" "$dir/manifest.restored.tsv"
    fx_log "$ID" undo "removed the git scan hooks from the global git config"
    if [ -n "$kept" ]; then echo "undo stopped for $kept: your later edits stopped the undo there, so it was left as it is; the hooks were removed" >&2; exit 6; fi
    echo "restored" ;;
esac
