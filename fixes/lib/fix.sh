#!/bin/bash -p
# Shared helpers for fix scripts: approval tokens, backups, restore, change log.
# Every location comes from this file's own place, never the environment, so a
# redirected approvals folder or a fake date/stat on PATH can't pass a token.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
unset BASH_ENV ENV CDPATH
FX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# A fix runs only from a copy that is exactly a signed release, checked before any other helper is loaded.
. "$FX_LIB_DIR/../../checks/lib/repo.sh"
devward_release_gate "$(cd "$FX_LIB_DIR/../.." && pwd -P)" || exit 4
# No DEVWARD_* setting from the caller reaches the checks a fix runs (timeouts, config folders).
for v in ${!DEVWARD_*}; do unset "$v"; done
DEVWARD_REPO="$(cd "$FX_LIB_DIR/../.." && pwd -P)"
DEVWARD_REPORTS="$DEVWARD_REPO/reports"
DEVWARD_PRIVATE_PATHS="$DEVWARD_REPO/private-paths"
DEVWARD_SYSROOT=""
export DEVWARD_REPO DEVWARD_REPORTS DEVWARD_PRIVATE_PATHS DEVWARD_SYSROOT
. "$DEVWARD_REPO/checks/lib/common.sh"
. "$DEVWARD_REPO/checks/lib/approval.sh"
FX_STAMP="$(date -u +%Y%m%dT%H%M%SZ)-$$"

fx_require_approval() {  # ID ACTION — consume a fresh token or refuse
  case "$2" in apply|undo) ;; *) echo "usage: $(basename "$0") apply|undo" >&2; exit 2 ;; esac
  devward_take_approval "$DEVWARD_REPORTS/.approvals" "$1" "$2" || exit 4
}

fx_backup() {  # ID FILE — non-zero if the backup fails; a dangling symlink is refused
  local dir="$DEVWARD_BACKUPS/$1/$FX_STAMP" n
  mkdir -p "$dir" || return 1
  if [ -L "$2" ] && [ ! -e "$2" ]; then return 1; fi
  if [ -f "$2" ]; then
    n="$(find "$dir" -name 'file-*' | grep -c .)"
    cp -p "$2" "$dir/file-$n" || return 1
    printf '%s\tfile-%s\n' "$2" "$n" >> "$dir/manifest.tsv" || return 1
  else
    printf '%s\tABSENT\n' "$2" >> "$dir/manifest.tsv" || return 1
  fi
}

fx_latest_backup() {  # ID — the newest backup folder not yet undone; status 1 if none
  local d dir=""
  for d in "$DEVWARD_BACKUPS/$1"/*/; do [ -f "$d/manifest.tsv" ] && dir="${d%/}"; done
  [ -n "$dir" ] || return 1
  printf '%s\n' "$dir"
}

fx_state() {  # FILE — its SHA-256, or ABSENT
  if [ -e "$1" ]; then shasum -a 256 < "$1" | awk '{print $1}'; else echo ABSENT; fi
}

fx_seal() {  # ID — record each backed-up file's state right after the change, so undo can spot later edits
  fx_seal_dir "$DEVWARD_BACKUPS/$1/$FX_STAMP"
}

fx_seal_dir() {  # BACKUP_DIR — write its sealed.tsv from the files' current states
  local f b
  [ -f "$1/manifest.tsv" ] || return 0
  while IFS="$(printf '\t')" read -r f b; do
    printf '%s\t%s\n' "$f" "$(fx_state "$f")"
  done < "$1/manifest.tsv" > "$1/sealed.tsv"
}

fx_check_seal() {  # BACKUP_DIR — exit 6, changing nothing, if a file differs from its sealed state
  local f h changed=""
  [ -f "$1/sealed.tsv" ] || return 0
  while IFS="$(printf '\t')" read -r f h; do
    [ "$(fx_state "$f")" = "$h" ] || changed="$changed, $(devward_tilde "$f")"
  done < "$1/sealed.tsv"
  [ -n "$changed" ] || return 0
  echo "undo stopped: these files changed after the fix, and undoing would lose those edits: ${changed#, }; backup kept in $(devward_tilde "$1")" >&2
  exit 6
}

fx_unchanged() {  # BACKUP_DIR FILE — true if FILE is as the fix left it, or nothing was sealed
  local f h
  [ -f "$1/sealed.tsv" ] || return 0
  while IFS="$(printf '\t')" read -r f h; do
    [ "$f" = "$2" ] && { [ "$(fx_state "$f")" = "$h" ]; return; }
  done < "$1/sealed.tsv"
  return 0
}

fx_restore_file() {  # BACKUP_DIR FILE — put one backed-up FILE back as it was before the fix
  local f b
  while IFS="$(printf '\t')" read -r f b; do
    [ "$f" = "$2" ] || continue
    if [ "$b" = ABSENT ]; then rm -f "$f"; else cp -p "$1/$b" "$f"; fi
    return
  done < "$1/manifest.tsv"
  return 1
}

fx_was_absent() {  # BACKUP_DIR FILE — true if FILE didn't exist before the fix
  awk -F'\t' -v f="$2" '$1 == f && $2 == "ABSENT" { found = 1 } END { exit !found }' "$1/manifest.tsv"
}

fx_drop_blank_created() {  # BACKUP_DIR FILE... — remove each FILE the fix created that is now blank
  local d="$1" f rc=0
  shift
  for f in "$@"; do
    { [ -f "$f" ] && [ ! -L "$f" ] && fx_was_absent "$d" "$f"; } || continue
    if grep -q '[^[:space:]]' "$f" 2>/dev/null; then continue
    elif [ $? -eq 1 ]; then rm -f "$f" || rc=1; fi  # 1 = readable and blank; 2 (unreadable) keeps it
  done
  return "$rc"
}

fx_restore() {  # ID — undo the most recent apply that hasn't been undone
  local dir f b bad=0
  dir="$(fx_latest_backup "$1")" || { echo "nothing to undo for $1" >&2; exit 5; }
  fx_check_seal "$dir"
  while IFS="$(printf '\t')" read -r f b; do
    if [ "$b" = ABSENT ]; then rm -f "$f" || { echo "could not remove $(devward_tilde "$f")" >&2; bad=1; }
    else cp -p "$dir/$b" "$f" || { echo "could not restore $(devward_tilde "$f")" >&2; bad=1; }; fi
  done < "$dir/manifest.tsv"
  if [ "$bad" -ne 0 ]; then
    [ -f "$dir/sealed.tsv" ] && fx_seal_dir "$dir"  # a retry must not mistake this partial undo for the person's edits
    echo "undo incomplete; backup kept" >&2; exit 6
  fi
  mv "$dir/manifest.tsv" "$dir/manifest.restored.tsv"
}

fx_log() {  # ID ACTION SUMMARY
  local log="$DEVWARD_REPORTS/change-log.md"
  [ -f "$log" ] || printf '| When (UTC) | Control | Action | What | Undo |\n|---|---|---|---|---|\n' > "$log"
  printf '| %s | %s | %s | %s | `fixes/macos/%s.sh undo` |\n' "$(date -u +%FT%TZ)" "$1" "$2" "$3" "$1" >> "$log"
}
