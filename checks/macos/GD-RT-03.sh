#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=GD-RT-03
# Sources, by numbered section below (checked 2026-11-19):
#   1 the no-terminal REPL loader — https://www.sonatype.com/blog/polinrider-loader-reappears-in-hijacked-npm-packages,
#     https://www.ox.security/blog/polinrider-returns-hijacked-npm-packages-use-ethereum-blockchain-to-conceal-malware-infrastructure/;
#     inline code in a long-running process — https://attack.mitre.org/techniques/T1059/
#   2 C2 addresses — the C2_IPS sources in fixes/files/git-scan-new-files's header; the last address —
#     https://cursor.com/blog/claude-code-extension-security-notice
#   3 the extension's backdoor files and key — https://cursor.com/blog/claude-code-extension-security-notice;
#     the loader's home folders — https://opensourcemalware.com/blog/polinrider-malware-found-in-2025-npm-packages,
#     https://github.com/Improwised/polinrider-scanner (the singular folder name, listed only there)
#   4 staging in temp folders — https://opensourcemalware.com/blog/polinrider-malware-found-in-2025-npm-packages,
#     https://github.com/Improwised/polinrider-scanner (one of the staged Python packages, listed only there)
#   5 start-up files — https://attack.mitre.org/techniques/T1546/004/
#   6 scheduled jobs — https://attack.mitre.org/techniques/T1053/003/, https://attack.mitre.org/techniques/T1543/001/
# The PolinRider / BeaverTail pack's C2 addresses (the Nov 2026 hijacked-npm loader's among them), and last, the
# trojanized Claude Code extension's server from https://cursor.com/blog/claude-code-extension-security-notice.
C2_IPS=" 103.179.143.219 136.0.9.8 154.91.0.103 166.88.134.62 166.88.134.75 166.88.134.82 166.88.4.2 166.88.54.158"
C2_IPS="$C2_IPS 181.214.149.148 188.43.33.249 198.105.127.210 202.155.8.173 23.27.120.142 23.27.13.135 23.27.13.43"
C2_IPS="$C2_IPS 23.27.13.72 23.27.20.143 23.27.20.187 23.27.202.27 95.135.181.151 134.209.82.225 "
high=""; low=""; skipped=""
hit() { high="$high$1"$'\n'; }   # a sign of live malware: fails
seen() { low="$low$1"$'\n'; }    # worth a look, not enough to fail
pub() { ! fortkeep_is_private "$1" || { skipped=" (a private folder was excluded)"; return 1; }; }  # PATH — outside every private folder
there() { pub "$1" && { [ -e "$1" ] || [ -L "$1" ]; }; }

# Temp folders, where loaders stage and run from: each spelling to match paths against, each real folder to look in.
tmps=""; tmpdirs=""
for t in "$(fortkeep_path /tmp)" "$(fortkeep_path /private/tmp)" "$(fortkeep_path /var/tmp)" "${TMPDIR:-}" "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)"; do
  t="${t%/}"; [ -n "$t" ] && [ -d "$t" ] || continue
  r="$(fortkeep_realpath "$t")"; tmps="$tmps$t"$'\n'"$r"$'\n'; tmpdirs="$tmpdirs$r"$'\n'
done
tmps="$(printf '%s' "$tmps" | awk 'length && !s[$0]++')"; tmpdirs="$(printf '%s' "$tmpdirs" | awk 'length && !s[$0]++')"

# 1. node or python running as a hidden loader. ps lists every process without root; lsof only your own.
if ! ps_info="$(ps -axo pid=,tty=,etime=,comm= 2>/dev/null)" || [ -z "$ps_info" ] \
  || ! ps_cmd="$(ps -axo pid=,command= 2>/dev/null)"; then
  fortkeep_result "$ID" ERROR "Could not list the running processes" "ps gave no process list"; exit 0
fi
pids="$(printf '%s\n' "$ps_info" | awk '{c = $4; for (i = 5; i <= NF; i++) c = c " " $i; sub(/.*\//, "", c)} tolower(c) ~ /^(node|python[0-9.]*)$/ {print $1}' | paste -sd, -)"
cwds=""; [ -z "$pids" ] || cwds="$(lsof -a -d cwd -Fn -p "$pids" 2>/dev/null)"
verdicts="$(FORTKEEP_PS="$ps_info" FORTKEEP_CMD="$ps_cmd" FORTKEEP_CWD="$cwds" FORTKEEP_TMPS="$tmps" /usr/bin/perl -e '
  our (%tty, %secs, %exe, %cmd, %cwd, @tmp); my $p;
  for (split /\n/, $ENV{FORTKEEP_PS}) {
    next unless /^\s*(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;
    my ($pid, $tt, $et, $ex) = ($1, $2, $3, $4);
    my @t = reverse split /[-:]/, $et;
    ($tty{$pid}, $exe{$pid}) = ($tt, $ex);
    $secs{$pid} = ($t[0] // 0) + 60 * ($t[1] // 0) + 3600 * ($t[2] // 0) + 86400 * ($t[3] // 0);
  }
  for (split /\n/, $ENV{FORTKEEP_CMD}) { $cmd{$1} = $2 if /^\s*(\d+)\s+(.*)$/ }
  for (split /\n/, $ENV{FORTKEEP_CWD}) { if (/^p(\d+)/) { $p = $1 } elsif (/^n(.*)/ && defined $p) { $cwd{$p} = $1 } }
  @tmp = grep { length } split /\n/, $ENV{FORTKEEP_TMPS};
  sub under { my $x = shift; for my $t (@tmp) { return 1 if $x eq $t || index($x, "$t/") == 0 } return 0 }
  for my $pid (sort { $a <=> $b } keys %exe) {
    (my $name = $exe{$pid}) =~ s{.*/}{};
    next unless $name =~ /^(node|python[0-9.]*)$/i;
    my $c = ($cmd{$pid} // "") . " "; my $bg = $tty{$pid} eq "??"; my $w = "$name (pid $pid)";
    if ($name =~ /^node$/i && $bg && $c =~ /\s(-i|--interactive)\s/) { print "H\t$w runs interactively with no terminal, as the Nov 2026 hijacked npm loader does\n"; next }
    if (under($exe{$pid})) { print "H\t$w runs from a temp folder\n"; next }
    my @why;
    # Python starts its multiprocessing workers and resource tracker as `-c` one-liners that live as long as the pool.
    # Exactly those one-liners: anything after them is code of its own.
    my $mp = $c =~ /\s-c\s+from multiprocessing\.(?:spawn import spawn_main; spawn_main|resource_tracker import main;main)\([\w\s,=]*\)(?:\s+--multiprocessing-fork)?\s*$/;
    push @why, "runs inline code" if $c =~ /\b(node|python[0-9.]*)\s+-[ce]\s/i && !$mp;
    push @why, "works in a temp folder" if defined $cwd{$pid} && under($cwd{$pid}) && $cwd{$pid} !~ m{/tmp/claude-\d+(?:/|\z)};
    next unless @why;
    # A loader keeps running with no terminal; tools run inline code for a moment.
    print(($bg && $secs{$pid} >= 60 ? "H" : "L") . "\t$w " . join(" and ", @why) . "\n");
  }')"
while IFS=$'\t' read -r k w; do
  case "$k" in H) hit "$w" ;; L) seen "$w" ;; esac
done <<EOF
$verdicts
EOF

# 2. A connection to a known C2 address. lsof lists your own processes' connections, which is where a loader runs.
fortkeep_has lsof || { fortkeep_result "$ID" ERROR "Could not list the network connections" "lsof is missing"; exit 0; }
for ip in $(lsof -nP -iTCP -sTCP:ESTABLISHED -Fn 2>/dev/null | awk -F'->' '/^n/ && NF > 1 {r = $2; sub(/:[0-9]+$/, "", r); gsub(/\[|\]/, "", r); sub(/^::ffff:/, "", r); print r}' | sort -u); do
  case "$C2_IPS" in *" $ip "*) hit "a connection to $ip, a known PolinRider C2 server" ;; esac
done

# 3. Known backdoor files: the 2026-10-29 trojanized Claude Code extension's, and the PolinRider loader's home folders.
for f in "$HOME/Library/LaunchAgents/com.apple.sysmond.plist" "$HOME/.config/.smt" "$HOME/.config/.smtk" "$HOME/.n2" "$HOME/.npl" "$HOME/.sysinfo"; do
  there "$f" && hit "$(fortkeep_tilde "$f") exists (a known backdoor file)"
done
k="$HOME/.ssh/authorized_keys"
pub "$k" && [ -f "$k" ] && grep -Eq '(^|[[:space:]])svc-telemetry[[:space:]]*$' "$k" 2>/dev/null \
  && hit "$(fortkeep_tilde "$k") lets in a key labelled svc-telemetry, the trojanized extension's backdoor"
for d in "$HOME/.node_modules" "$HOME/.node_module"; do
  there "$d" || continue
  deps="$(jq -r '[.dependencies, .devDependencies, .optionalDependencies, .peerDependencies | objects | keys[]] | .[]' "$d/package.json" 2>/dev/null)"
  if [ -d "$d/node_modules/socket.io-client" ] || { printf '%s\n' "$deps" | grep -qx axios && printf '%s\n' "$deps" | grep -qx socket.io-client; }; then
    hit "$(fortkeep_tilde "$d") holds the BeaverTail loader's packages"
  else
    seen "$(fortkeep_tilde "$d") exists without the BeaverTail packages"
  fi
done

# 4. Loader staging in the temp folders: an npm stage, staged pip packages, a dotfile named after you in base64.
me="$(id -un)"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  if [ -d "$t/.npm" ]; then
    staged=0
    for s in "$t/.npm"/*; do
      [ -d "$s" ] && [ ! -L "$s" ] || continue
      printf '%s\n' "${s##*/}" | grep -Eq '^[A-Za-z0-9_.-]+\$[A-Za-z0-9_.-]+_[0-9]{6}_[0-9]{6}$' || continue
      staged=1; hit "$(fortkeep_tilde "$s") is a loader staging folder"
    done
    [ "$staged" -eq 1 ] || seen "$(fortkeep_tilde "$t/.npm") exists"
  fi
  pip=0
  if [ -d "$t/.pip" ]; then
    if find "$t/.pip" -maxdepth 7 \( -name Cryptodome -o -name 'Cryptodome[-.]*' -o -name pyzipper -o -name 'pyzipper[-.]*' \
      -o -name secretstorage -o -name 'secretstorage[-.]*' -o -name jeepney -o -name 'jeepney[-.]*' -o -name dbus_next \
      -o -name 'dbus_next[-.]*' -o -name portalocker -o -name 'portalocker[-.]*' \) 2>/dev/null | grep -q .; then
      pip=1; hit "$(fortkeep_tilde "$t/.pip") holds the loader's staged Python packages"
    else
      seen "$(fortkeep_tilde "$t/.pip") exists"
    fi
  fi
  if [ -f "$t/get-pip.py" ]; then
    if [ "$pip" -eq 1 ]; then hit "$(fortkeep_tilde "$t/get-pip.py") sits beside the staged packages"; else seen "$(fortkeep_tilde "$t/get-pip.py") exists"; fi
  fi
  for f in "$t"/.[!.]*; do
    [ -f "$f" ] && [ ! -L "$f" ] && [ "$(stat -f %z "$f" 2>/dev/null || echo 99)" -lt 33 ] || continue
    n="${f##*/}"
    /usr/bin/perl -MMIME::Base64 -e '
      my ($n, $me) = @ARGV; exit 1 unless $n =~ /^[A-Za-z0-9+\/_-]+=*$/;
      (my $s = $n) =~ tr{_-}{/+}; $s .= "=" x (-length($s) % 4);
      exit(decode_base64($s) eq $me ? 0 : 1)' "${n#.}" "$me" && hit "$(fortkeep_tilde "$f") is named after you in base64, as the loader marks a Mac"
  done
done <<EOF
$tmpdirs
EOF

# 5. Start-up files that fetch, decode or run inline code each time a shell or npm starts. Line numbers only: a line can hold a token.
# Only a download that is run, or decoded text piped into a shell, is a sign; aliases and helper functions that decode
# or run a one-liner are common, so they are only noted.
w='([^[:alnum:]_]|$)'; sh="(ba|z|da)?sh$w"
# python or node runs the download only when it reads its program from stdin: nothing after it, or a lone -.
stdin_run="(python[0-9.]*|node)([[:space:]]+-)?[[:space:]]*([;&|)'\"]|$)"
fetch_run="(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?($sh|$stdin_run)|(eval|source|\.)[[:space:]]+[\"']?(<\(|\\\$\()[[:space:]]*(curl|wget)|(sh|bash|zsh)[[:space:]]+-c[[:space:]]+[\"']?\\\$\((curl|wget)"
decode_run="base64[[:space:]]+(-d|-D|--decode)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?$sh"
inline="base64[[:space:]]+(-d|-D|--decode)|(^|[^[:alnum:]_])node[[:space:]]+-e$w|(^|[^[:alnum:]_])python[0-9.]*[[:space:]]+-c$w"
for f in .zshrc .zshenv .zprofile .zlogin .bashrc .bash_profile .profile .npmrc .config/fish/config.fish "$HOME"/.config/fish/conf.d/*.fish; do
  case "$f" in /*) ;; *) f="$HOME/$f" ;; esac
  { pub "$f" && [ -f "$f" ]; } || continue
  lines="$(grep -nE "$fetch_run|$decode_run|$inline" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#')"
  while IFS= read -r n; do
    [ -n "$n" ] && hit "$(fortkeep_tilde "$f") line $n runs downloaded or decoded code at start-up"
  done <<EOF
$(printf '%s\n' "$lines" | grep -E "^[0-9]+:.*($fetch_run|$decode_run)" | cut -d: -f1)
EOF
  while IFS= read -r n; do
    [ -n "$n" ] && seen "$(fortkeep_tilde "$f") line $n decodes or runs inline code at start-up"
  done <<EOF
$(printf '%s\n' "$lines" | grep -vE "^[0-9]+:.*($fetch_run|$decode_run)" | cut -d: -f1)
EOF
done

# 6. Scheduled jobs whose command runs inline code or a loader staged in a temp folder.
sus() {  # reads commands, one per line; prints the number of each that runs inline code or a staged loader
  FORTKEEP_TMPS="$tmps" /usr/bin/perl -ne '
    BEGIN { our $re = join "|", (map { quotemeta($_) . q{/\.(npm|pip)\b} } grep { length } split /\n/, $ENV{FORTKEEP_TMPS}), q{/\.node_modules?\b} }
    our $re; print "$.\n" if "$_ " =~ /(node|python[0-9.]*)\s+-[ce]\s/i || /$re/'
}
if ct="$(crontab -l 2>/dev/null)"; then
  for n in $(printf '%s\n' "$ct" | sed 's/^[[:space:]]*#.*//' | sus); do hit "your crontab line $n runs inline code or a staged loader"; done
fi
for d in "$HOME/Library/LaunchAgents" "$(fortkeep_path /Library/LaunchAgents)" "$(fortkeep_path /Library/LaunchDaemons)"; do
  pub "$d" || continue
  for p in "$d"/*.plist; do
    [ -f "$p" ] || continue
    c="$(plutil -extract Program raw -o - "$p" 2>/dev/null) $(plutil -extract ProgramArguments json -o - "$p" 2>/dev/null | jq -r 'join(" ")' 2>/dev/null)"
    [ -z "$(printf '%s\n' "$c" | tr '\n' ' ' | sus)" ] || hit "$(fortkeep_tilde "$p") runs inline code or a staged loader"
  done
done

high="$(printf '%s' "$high" | sed '/^$/d')"; low="$(printf '%s' "$low" | sed '/^$/d')"
n="$(fortkeep_count "$high")"
if [ "$n" -gt 0 ]; then
  fortkeep_result "$ID" FAIL "$n sign(s) of live malware on this Mac" "$(fortkeep_join "$(printf '%s\n' "$high" | head -5)" '; '). Don't open new work or type passwords; type /if-red.$skipped"
else
  note="$(fortkeep_join "$low" '; ')$skipped"
  fortkeep_result "$ID" PASS "No live malware process, C2 connection or known backdoor file" "${note# }"
fi
