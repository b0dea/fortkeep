#!/bin/bash
# Source it, don't run it. Which fixes are applied, for fortkeep uninstall. Apart from fix.sh, which a fix script
# sources: that one refuses a copy that isn't a signed release, and uninstall must work from any copy. It needs
# FORTKEEP_BACKUPS and FORTKEEP_REPORTS (checks/lib/common.sh).
FX_FIXES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../macos" && pwd -P)"

# A fix whose change keeps working without fortkeep says so with this exact line in its script. Its backups go with
# fortkeep's state folder at uninstall; every other applied fix, a new one included, must be undone first.
FX_STAYS_MARKER="# fortkeep: stays after uninstall"

fx_applied() {  # prints "ID<TAB>stays|needs-fortkeep<TAB>what the change log says it did" for each applied fix
  # A fix is applied while one of its backups still has a manifest.tsv: undo renames it (fx_restore).
  local m id seen="" kind what
  for m in "$FORTKEEP_BACKUPS"/*/*/manifest.tsv; do
    [ -f "$m" ] || continue
    id="${m%/*/manifest.tsv}"; id="${id##*/}"
    case " $seen " in *" $id "*) continue ;; esac
    seen="$seen $id"
    if grep -qxF "$FX_STAYS_MARKER" "$FX_FIXES_DIR/$id.sh" 2>/dev/null; then kind=stays; else kind=needs-fortkeep; fi
    what="$(awk -F' [|] ' -v id="$id" '$2 == id && $3 == "apply" { w = $4 } END { print w }' "$FORTKEEP_REPORTS/change-log.md" 2>/dev/null)"
    printf '%s\t%s\t%s\n' "$id" "$kind" "${what:-applied}"
  done
}
