#!/bin/bash
# The Terminal look of bin/fortkeep for a person at a terminal: colour, the progress line and the menu. Source it,
# don't run it. ui_on decides; a pipe, an agent, CI, NO_COLOR or TERM=dumb get today's plain text. The results table
# itself is drawn by ui.jq.

ui_on() {  # FD — true when FD is a terminal that may show colour (https://no-color.org)
  [ -t "$1" ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]
}

ui_cols() {  # the terminal's width: tput reads it from whichever of stdout or stderr is the terminal, and honours COLUMNS
  local c
  c="$(tput cols)" || c=80
  case "$c" in ''|*[!0-9]*) c=80 ;; esac
  [ "$c" -ge 40 ] || c=40
  echo "$c"
}

UI_BOLD=$'\033[1m' UI_GRAY=$'\033[90m' UI_GREEN=$'\033[32m' UI_YELLOW=$'\033[33m' UI_CYAN=$'\033[36m' UI_OFF=$'\033[0m'

# Whatever the menu or the progress line changed in the terminal goes back on exit. bash runs the EXIT trap on Ctrl-C
# too, so one trap covers both.
UI_STTY="" UI_CURSOR_FD=""
ui_restore() {
  if [ -n "$UI_STTY" ]; then stty "$UI_STTY" 2>/dev/null; UI_STTY=""; fi
  # On its own line, which a progress line cut short by Ctrl-C would otherwise share with the prompt; line wrap back on
  # (the menu turns it off).
  if [ -n "$UI_CURSOR_FD" ]; then printf '\r\033[K\033[?25h\033[?7h' >&"$UI_CURSOR_FD"; UI_CURSOR_FD=""; fi
}
ui_hide_cursor() { trap ui_restore EXIT; UI_CURSOR_FD="$1"; printf '\033[?25l' >&"$1"; }  # FD

# The progress line. checks/run.sh prints "fortkeep: N/TOTAL ID (Ns so far)" on stderr as each check starts; its
# output is its contract with agents, so it stays as it is and this reads it. ui_ticker's lines move the spinner
# between them. The caller hides the cursor (ui_hide_cursor 2), so its own trap shows it again.
UI_TICK="fortkeep-ui: tick"
ui_ticker() { while sleep 0.1 && echo "$UI_TICK"; do :; done; }  # stops once nothing reads it

ui_progress() {  # reads checks/run.sh's stderr (and ui_ticker's lines); draws one line on stderr that keeps updating
  local line n=0 total=0 id="" f=0 cols bar w full tail start=$SECONDS
  local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  cols="$(ui_cols)"
  while IFS= read -r line; do
    case "$line" in
      "$UI_TICK") f=$(( (f + 1) % ${#frames[@]} )) ;;
      "fortkeep: "[0-9]*/[0-9]*" "*)
        line="${line#fortkeep: }"; n="${line%%/*}"; line="${line#*/}"; total="${line%% *}"; line="${line#* }"; id="${line%% *}" ;;
      *) printf '\r\033[K%s\n' "$line" >&2; continue ;;  # anything else (an error) prints as it is
    esac
    [ "$total" -gt 0 ] 2>/dev/null || continue
    # The bar shows the checks done; the counter, the one running.
    w=16; full=$(( (n - 1) * w / total )); bar=""
    while [ "${#bar}" -lt "$w" ]; do if [ "${#bar}" -lt "$full" ]; then bar="$bar#"; else bar="$bar-"; fi; done
    bar="${bar//#/█}"; bar="${bar//-/░}"
    tail="$n/$total · $id · $((SECONDS - start))s"
    # Never wider than the terminal, or each redraw would leave a wrapped line behind: drop the label, then the bar.
    if [ $(( 25 + w + ${#tail} )) -lt "$cols" ]; then
      printf '\r\033[K  %s %sChecking this Mac%s  %s%s%s  %s' "$UI_CYAN${frames[f]}$UI_OFF" "$UI_BOLD" "$UI_OFF" \
        "$UI_GREEN" "$bar" "$UI_OFF" "$tail" >&2
    elif [ $(( 6 + w + ${#tail} )) -lt "$cols" ]; then
      printf '\r\033[K  %s %s%s%s  %s' "$UI_CYAN${frames[f]}$UI_OFF" "$UI_GREEN" "$bar" "$UI_OFF" "$tail" >&2
    else
      printf '\r\033[K  %s %s' "$UI_CYAN${frames[f]}$UI_OFF" "$n/$total" >&2
    fi
  done
  printf '\r\033[K' >&2
}

ui_status() {  # SIGNED COPY LAST NEXT — the block above the menu; SIGNED is empty for a copy that isn't a signed release
  local mark="$UI_GREEN✓$UI_OFF"
  [ -n "$1" ] || mark="$UI_YELLOW!$UI_OFF"
  printf '%sfortkeep%s  %sa security checkup for this Mac%s\n\n' "$UI_BOLD" "$UI_OFF" "$UI_GRAY" "$UI_OFF"
  printf '  %sThis copy%s    %s %s\n' "$UI_GRAY" "$UI_OFF" "$mark" "$2"
  printf '  %sLast check%s   %s\n' "$UI_GRAY" "$UI_OFF" "$3"
  printf '  %sNext%s         %s\n\n' "$UI_GRAY" "$UI_OFF" "$4"
}

# The menu. ui_key reads one key: up, down, enter, quit or the character itself. A closed input quits.
ui_key() {
  local k rest=""
  IFS= read -rsn1 k || { echo quit; return; }
  case "$k" in
    $'\033') IFS= read -rsn2 -t 1 rest
      case "$rest" in '[A'|OA) echo up ;; '[B'|OB) echo down ;; '') echo quit ;; *) echo other ;; esac ;;
    '') echo enter ;;
    k|K) echo up ;;
    j|J) echo down ;;
    q|Q) echo quit ;;
    *) printf '%s\n' "$k" ;;
  esac
}

ui_menu_items() {  # SELECTED COLS ITEM... — one line per item ("label|what it does"), then the keys
  local sel="$1" cols="$2" i=0 item label what; shift 2
  for item in "$@"; do
    i=$((i + 1)); label="${item%%|*}"; what="${item#*|}"
    # A description only where it fits on the line.
    [ $(( 34 + ${#what} )) -lt "$cols" ] || what=""
    if [ "$i" -eq "$sel" ]; then
      printf '\r\033[K%s➤ %d  %-28s%s %s%s%s\n' "$UI_CYAN$UI_BOLD" "$i" "$label" "$UI_OFF" "$UI_GRAY" "$what" "$UI_OFF"
    else
      printf '\r\033[K  %d  %-28s %s%s%s\n' "$i" "$label" "$UI_GRAY" "$what" "$UI_OFF"
    fi
  done
  printf '\r\033[K\n\r\033[K%s↑↓ or j/k to move · Enter to choose · 1-%d · q to quit%s\n' "$UI_GRAY" "$#" "$UI_OFF"
}

ui_menu() {  # ITEM... — draws the menu on stdout; returns the number of the item chosen (from 1); quit picks the last
  local sel=1 n=$# cols key items=("$@")
  cols="$(ui_cols)"
  UI_STTY="$(stty -g)" || UI_STTY=""
  ui_hide_cursor 1
  # Keys typed between two reads aren't echoed under the menu, and with line wrap off every line is one row, so the
  # redraw's count of rows to go back up holds in a narrow window too.
  stty -echo -icanon 2>/dev/null; printf '\033[?7l'
  ui_menu_items "$sel" "$cols" "$@"
  while :; do
    key="$(ui_key)"
    case "$key" in
      up) [ "$sel" -le 1 ] || sel=$((sel - 1)) ;;
      down) [ "$sel" -ge "$n" ] || sel=$((sel + 1)) ;;
      enter) break ;;
      quit) sel="$n"; break ;;
      [1-9]) if [ "$key" -le "$n" ]; then sel="$key"; break; fi ;;
    esac
    printf '\033[%dA' $((n + 2))
    ui_menu_items "$sel" "$cols" "$@"
  done
  # The menu folds into the item chosen, so what it starts reads on from there.
  printf '\033[%dA\033[J%s➤ %s%s\n' $((n + 2)) "$UI_CYAN$UI_BOLD" "${items[sel - 1]%%|*}" "$UI_OFF"
  ui_restore
  return "$sel"
}
