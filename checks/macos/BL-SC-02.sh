#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SC-02
SHIMS="$HOME/.safe-chain/shims"
[ -x "$SHIMS/npm" ] || { devward_result "$ID" FAIL "No Safe Chain npm shim" "Install Safe Chain first (BL-SC-01)"; exit 0; }
# Every command Safe Chain has a shim for (npm, npx, pnpm, pip, pip3, python3, uv, ...) must resolve to it: one
# later PATH line in a start-up file can put a real pip ahead of the shims for that shell and all it starts.
names=""; k=0
for f in "$SHIMS"/*; do
  n="${f##*/}"
  case "$n" in *[!A-Za-z0-9._+-]*) continue ;; esac
  [ -x "$f" ] && [ ! -d "$f" ] || continue
  names="$names $n"; k=$((k + 1))
done
# Each answer is prefixed, so whatever a start-up file prints isn't read as one.
snip="for n in$names; do printf 'W:%s %s\\n' \"\$n\" \"\$(/usr/bin/which \"\$n\" 2>/dev/null)\"; done"
total=0; good=0; bad=""; unknown=""; silent=""
while IFS= read -r t; do
  [ -n "$t" ] || continue
  total=$((total + 1))
  out="$(devward_shell_probe "$t" "$snip")"; rc=$?
  if [ "$rc" -eq 142 ]; then unknown="$unknown, $(devward_shell_label "$t")"; continue; fi
  answers="$(printf '%s\n' "$out" | sed -n 's/^W:\([^ ][^ ]* \)/\1/p')"
  # A shell that ended early or printed nothing is undecided, never a pass.
  if [ "$(devward_count "$answers")" -ne "$k" ]; then silent="$silent, $(devward_shell_label "$t")"; continue; fi
  wrong=""; where=""
  while IFS= read -r a; do
    n="${a%% *}"; p="${a#* }"
    [ "$p" = "$SHIMS/$n" ] && continue
    wrong="$wrong, $n"
    [ -z "$where" ] && [ -n "$p" ] && where=" from $(devward_tilde "$(dirname "$p")")"
  done <<EOF
$answers
EOF
  if [ -z "$wrong" ]; then good=$((good + 1)); else bad="$bad, $(devward_shell_label "$t") (${wrong#, }$where)"; fi
done <<EOF
$(devward_shell_types)
EOF
ev="$good of $total shell types find all $k Safe Chain commands at the shims"
if [ -n "$bad" ]; then devward_result "$ID" FAIL "$ev" "Not first in: ${bad#, }${unknown:+. Timed out: ${unknown#, }}${silent:+. No answer from: ${silent#, }}"
elif [ -n "$unknown" ]; then devward_result "$ID" ERROR "$ev" "Timed out: ${unknown#, }${silent:+. No answer from: ${silent#, }}"
elif [ -n "$silent" ]; then devward_result "$ID" ERROR "$ev" "No answer from: ${silent#, } (a start-up file may end the shell early)"
else devward_result "$ID" PASS "$ev"; fi
