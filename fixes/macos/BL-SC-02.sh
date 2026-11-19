#!/bin/bash -p
# Puts Safe Chain's shims first on PATH in every shell type and pins the age gate. Usage: apply | undo
. "$(dirname "$0")/../lib/fix.sh"
ID=BL-SC-02
fx_require_approval "$ID" "${1:-}"
DEST="$HOME/.config/devward/path-front.sh"
MARK="# devward BL-SC-02"
LINE="[ -r \"\$HOME/.config/devward/path-front.sh\" ] && . \"\$HOME/.config/devward/path-front.sh\"  $MARK"
passes() { [ "$(/bin/bash -p "$DEVWARD_REPO/checks/macos/$1.sh" | jq -r .status)" = PASS ]; }
changed=0
stop() {  # MESSAGE — finish as MANUAL; changes made so far are logged and can be undone
  [ "$changed" -eq 1 ] && { fx_seal "$ID"; fx_log "$ID" apply "Safe Chain shims first and age gate pinned (partly)"; }
  echo "MANUAL: $1"; exit 3
}
case "$1" in
  apply)
    [ -x "$HOME/.safe-chain/shims/npm" ] || stop "install Safe Chain first, including the --ci step (see BL-SC-01)"
    if passes BL-SC-02 && passes BL-SC-04; then echo "nothing to change: the shims come first and the age gate is pinned"; exit 0; fi
    targets="$(printf '%s\n' "$HOME/.zshenv" "$HOME/.zshrc" "$HOME/.zlogin"
      if [ -f "$HOME/.bash_profile" ]; then printf '%s\n' "$HOME/.bash_profile"
      elif [ -f "$HOME/.profile" ]; then printf '%s\n' "$HOME/.profile"; fi
      [ -f "$HOME/.bashrc" ] && printf '%s\n' "$HOME/.bashrc")"
    mkdir -p "$(dirname "$DEST")" || stop "could not create $(devward_tilde "$(dirname "$DEST")")"
    if ! cmp -s "$DEVWARD_REPO/fixes/files/path-front.sh" "$DEST"; then
      fx_backup "$ID" "$DEST" || stop "could not back up $(devward_tilde "$DEST")"
      cp "$DEVWARD_REPO/fixes/files/path-front.sh" "$DEST" || stop "could not write $(devward_tilde "$DEST")"
      changed=1
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -qF "$MARK" "$f" 2>/dev/null && continue
      fx_backup "$ID" "$f" || stop "could not back up $(devward_tilde "$f")"
      printf '\n%s\n' "$LINE" >> "$f" || stop "could not update $(devward_tilde "$f")"
      changed=1
    done <<EOF
$targets
EOF
    [ "$changed" -eq 1 ] && { fx_seal "$ID"; fx_log "$ID" apply "Safe Chain shims first and age gate pinned in shell start-up files"; }
    changed=0
    if passes BL-SC-02 && passes BL-SC-04; then echo "done: the shims come first in every shell type; open a new Terminal window to use them"; exit 0; fi
    stop "the line is in place, but something later in a start-up file still changes PATH or the age gate. Move the line marked devward to the very end of each file listed by the BL-SC-02 check, then re-check" ;;
  undo)
    # Removes only what apply added: the marked line in each start-up file, then the PATH file if
    # it's still as apply left it. A failure stops before the PATH file, so a retry is safe.
    dir="$(fx_latest_backup "$ID")" || { echo "nothing to undo for $ID" >&2; exit 5; }
    kept=""; bad=0; dest=0
    while IFS="$(printf '\t')" read -r f _; do
      [ "$f" = "$DEST" ] && { dest=1; continue; }
      [ -f "$f" ] || continue
      [ -r "$f" ] || { bad=1; continue; }  # perl -p exits 0 on a file it can't open, which would wipe it
      # The line with the blank line apply put before it, else the marked line alone: never the newlines around it.
      out="$(LINE="$LINE" MARK="$MARK" perl -0777 -pe 's/(\A|\n)\n\Q$ENV{LINE}\E(?:\n|\z)/$1/ or s/^[^\n]*\Q$ENV{MARK}\E[^\n]*\n?//m' "$f" && printf x)" || { bad=1; continue; }
      printf '%s' "${out%x}" > "$f" || { bad=1; continue; }
      fx_drop_blank_created "$dir" "$f" || bad=1
    done < "$dir/manifest.tsv"
    if [ "$bad" -eq 0 ] && [ "$dest" -eq 1 ]; then
      if fx_unchanged "$dir" "$DEST"; then fx_restore_file "$dir" "$DEST" || bad=1; else kept="$(devward_tilde "$DEST")"; fi
    fi
    if [ "$bad" -ne 0 ]; then echo "undo incomplete; backup kept in $(devward_tilde "$dir")" >&2; exit 6; fi
    mv "$dir/manifest.tsv" "$dir/manifest.restored.tsv"
    fx_log "$ID" undo "removed the devward line from shell start-up files"
    if [ -n "$kept" ]; then echo "undo stopped for $kept: your later edits stopped the undo there, so it was left as it is; the line in your start-up files was removed" >&2; exit 6; fi
    echo "restored" ;;
esac
