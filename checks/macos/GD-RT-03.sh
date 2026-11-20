#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=GD-RT-03
# Sources, by numbered section below (checked 2026-11-19; entries marked * checked 2026-11-20):
#   1 the no-terminal REPL loader — https://www.sonatype.com/blog/polinrider-loader-reappears-in-hijacked-npm-packages,
#     https://www.ox.security/blog/polinrider-returns-hijacked-npm-packages-use-ethereum-blockchain-to-conceal-malware-infrastructure/;
#     inline code in a long-running process — https://attack.mitre.org/techniques/T1059/;
#     * a detached python reading its program from stdin — https://github.com/OpenSourceMalware/PolinRider/issues/12;
#     * the reverse SSH tunnel to port 22 — https://cursor.com/blog/claude-code-extension-security-notice
#   2 C2 addresses — the C2_IPS sources in fixes/files/git-scan-new-files's header; the trojanized extension's —
#     https://cursor.com/blog/claude-code-extension-security-notice; * the accurasofthire loader's four —
#     https://www.stepsecurity.io/blog/accurasofthire-fake-interview-developer-machines; * GhostAction's —
#     https://blog.gitguardian.com/ghostaction-x-polinrider/; * Miasma's — https://research.jfrog.com/post/miasma-worm-returns-to-npm/
#   3 the extension's backdoor files and key — https://cursor.com/blog/claude-code-extension-security-notice;
#     the loader's home folders — https://opensourcemalware.com/blog/polinrider-malware-found-in-2025-npm-packages,
#     https://github.com/Improwised/polinrider-scanner (the singular folder name, listed only there);
#     * the loader's .npm-ws files — https://github.com/OpenSourceMalware/PolinRider/issues/12,
#     https://blog.greenflagged.dev/posts/2026-11-03-adminide-stack-eth-dead-drop/;
#     * the extension's 2.1.312 and 2.1.313 folders — https://cursor.com/blog/claude-code-extension-security-notice;
#     * ChainDrop's monitor (an installer the sample carried, not yet seen run) — https://unit42.paloaltonetworks.com/chaindrop-npm-worm-analysis/;
#     * Miasma's files — https://research.jfrog.com/post/miasma-worm-returns-to-npm/;
#     * MacSync's log, folder and label — https://securelist.com/macsync-new-version/121383/;
#     * AMOS's LaunchDaemon and ~/.agent loop — https://www.sophos.com/en-us/blog/why-amos-matters-the-macos-malware-stealing-data-at-scale,
#     https://www.infostealers.com/article/atomic-macos-stealer-now-includes-a-backdoor-for-persistent-access/
#     (~/.mainhelper is listed by Sophos alone, with no description: only noted)
#   4 staging in temp folders — https://opensourcemalware.com/blog/polinrider-malware-found-in-2025-npm-packages,
#     https://github.com/Improwised/polinrider-scanner (one of the staged Python packages, listed only there);
#     * the extension's .stk_ file — https://cursor.com/blog/claude-code-extension-security-notice;
#     * MacSync's .sys- payload — https://securelist.com/macsync-new-version/121383/
#   5 start-up files — https://attack.mitre.org/techniques/T1546/004/; * Miasma's profile block —
#     https://research.jfrog.com/post/miasma-worm-returns-to-npm/; * MacSync's .repair-run lines in ~/.zshrc and the
#     global git hooks — https://securelist.com/macsync-new-version/121383/
#   6 scheduled jobs — https://attack.mitre.org/techniques/T1053/003/, https://attack.mitre.org/techniques/T1543/001/;
#     * GhostAction's cron line — https://blog.gitguardian.com/ghostaction-x-polinrider/
#   7 * editor and app start-up files patched by PolinRider's second stage, its tags and its tab-padded payload —
#     https://blog.greenflagged.dev/posts/2026-11-03-adminide-stack-eth-dead-drop/, https://blog.gitguardian.com/ghostaction-x-polinrider/
# The PolinRider / BeaverTail pack's C2 addresses (the Nov 2026 hijacked-npm loader's and the accurasofthire loader's
# among them), and last, the trojanized Claude Code extension's server from https://cursor.com/blog/claude-code-extension-security-notice.
C2_IPS=" 103.179.143.219 136.0.9.8 154.91.0.103 166.88.134.62 166.88.134.75 166.88.134.82 166.88.4.2 166.88.54.158"
C2_IPS="$C2_IPS 181.214.149.148 188.43.33.249 198.105.127.210 202.155.8.173 23.27.120.142 23.27.13.135 23.27.13.43"
C2_IPS="$C2_IPS 23.27.13.72 23.27.20.143 23.27.20.187 23.27.202.27 95.135.181.151 103.179.142.155 91.218.183.174"
C2_IPS="$C2_IPS 193.247.144.38 166.88.73.46 134.209.82.225 "
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

# 1. node or python running as a hidden loader, or ssh tunnelling this Mac out. ps lists every process without root;
# lsof only your own.
if ! ps_info="$(ps -axo pid=,tty=,etime=,comm= 2>/dev/null)" || [ -z "$ps_info" ] \
  || ! ps_cmd="$(ps -axo pid=,command= 2>/dev/null)" || ! ps_ppid="$(ps -axo pid=,ppid= 2>/dev/null)" || [ -z "$ps_ppid" ]; then
  fortkeep_result "$ID" ERROR "Could not list the running processes" "ps gave no process list"; exit 0
fi
pids="$(printf '%s\n' "$ps_info" | awk '{c = $4; for (i = 5; i <= NF; i++) c = c " " $i; sub(/.*\//, "", c)} tolower(c) ~ /^(node|python[0-9.]*)$/ {print $1}' | paste -sd, -)"
cwds=""; [ -z "$pids" ] || cwds="$(lsof -a -d cwd -Fn -p "$pids" 2>/dev/null)"
verdicts="$(FORTKEEP_PS="$ps_info" FORTKEEP_CMD="$ps_cmd" FORTKEEP_PPID="$ps_ppid" FORTKEEP_CWD="$cwds" FORTKEEP_TMPS="$tmps" /usr/bin/perl -e '
  our (%tty, %secs, %exe, %cmd, %ppid, %cwd, @tmp); my $p;
  for (split /\n/, $ENV{FORTKEEP_PS}) {
    next unless /^\s*(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;
    my ($pid, $tt, $et, $ex) = ($1, $2, $3, $4);
    my @t = reverse split /[-:]/, $et;
    ($tty{$pid}, $exe{$pid}) = ($tt, $ex);
    $secs{$pid} = ($t[0] // 0) + 60 * ($t[1] // 0) + 3600 * ($t[2] // 0) + 86400 * ($t[3] // 0);
  }
  for (split /\n/, $ENV{FORTKEEP_CMD}) { $cmd{$1} = $2 if /^\s*(\d+)\s+(.*)$/ }
  for (split /\n/, $ENV{FORTKEEP_PPID}) { $ppid{$1} = $2 if /^\s*(\d+)\s+(\d+)\s*$/ }
  for (split /\n/, $ENV{FORTKEEP_CWD}) { if (/^p(\d+)/) { $p = $1 } elsif (/^n(.*)/ && defined $p) { $cwd{$p} = $1 } }
  @tmp = grep { length } split /\n/, $ENV{FORTKEEP_TMPS};
  sub under { my $x = shift; for my $t (@tmp) { return 1 if $x eq $t || index($x, "$t/") == 0 } return 0 }
  for my $pid (sort { $a <=> $b } keys %exe) {
    (my $name = $exe{$pid}) =~ s{.*/}{};
    my $c = ($cmd{$pid} // "") . " "; my $bg = $tty{$pid} eq "??"; my $w = "$name (pid $pid)";
    # Any port on the far side, forwarded to the SSH server here; autossh keeps it up.
    if ($name =~ /^(auto)?ssh$/ && $c =~ /\s-R\s*\*:0:localhost:22\s/) { print "H\t$w opens a reverse tunnel into this Mac\x27s SSH, as the trojanized Claude Code extension does\n"; next }
    next unless $name =~ /^(node|python[0-9.]*)$/i;
    if ($name =~ /^node$/i && $bg && $c =~ /\s(-i|--interactive)\s/) { print "H\t$w runs interactively with no terminal, as the Nov 2026 hijacked npm loader does\n"; next }
    # The stealer double-forks to launchd and is fed its code through stdin, leaving no file.
    if ($name =~ /^python/i && $bg && ($ppid{$pid} // "") eq "1" && $secs{$pid} >= 60 && $c =~ /\s-u\s+-\s$/) { print "H\t$w runs code fed through stdin, detached with no terminal, as the PolinRider stealer does\n"; next }
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
  case "$ip" in
    193.32.204.199) hit "a connection to $ip, GhostAction's C2 server" ;;
    85.137.53.71) hit "a connection to $ip, the Miasma worm's C2 server" ;;
  esac
done

# 3. Known backdoor files and folders, by family.
for f in "$HOME/Library/LaunchAgents/com.apple.sysmond.plist" "$HOME/.config/.smt" "$HOME/.config/.smtk" "$HOME/.n2" "$HOME/.npl" "$HOME/.sysinfo"; do
  there "$f" && hit "$(fortkeep_tilde "$f") exists (a known backdoor file)"
done
bd() {  # FAMILY PATH... — each PATH that exists is a known file of FAMILY
  local fam="$1" f; shift
  for f in "$@"; do there "$f" && hit "$(fortkeep_tilde "$f") exists (a known $fam file)"; done; return 0
}
bd ChainDrop "$HOME/Library/LaunchAgents/com.user.gh-token-monitor.plist" "$HOME/.local/bin/gh-token-monitor.sh" "$HOME/.config/gh-token-monitor"
bd Miasma "$HOME/Library/Application Support/NodeJS/sync.js" "$HOME/.config/.miasma" "$HOME/Library/Application Support/com.apple.spotlight/index-v2.cache"
bd MacSync "$HOME/Library/Logs/.sysnotif-agent.log"
bd AMOS "$(fortkeep_path /Library/LaunchDaemons/com.finder.helper.plist)"
# Names common enough to be someone's own: only noted, or a hit only with what the malware writes in them.
there "$HOME/Library/Application Support/System" && seen "$(fortkeep_tilde "$HOME/Library/Application Support/System") exists: macOS makes no such folder, MacSync does"
there "$HOME/.mainhelper" && seen "$(fortkeep_tilde "$HOME/.mainhelper") exists, a file name the AMOS backdoor uses"
a="$HOME/.agent"
pub "$a" && [ -f "$a" ] && [ "$(stat -f %z "$a" 2>/dev/null || echo 65536)" -lt 65536 ] && grep -qF /dev/console "$a" 2>/dev/null \
  && grep -qF .helper "$a" 2>/dev/null && hit "$(fortkeep_tilde "$a") keeps running .helper as whoever is logged in, as the AMOS backdoor does"
k="$HOME/.ssh/authorized_keys"
pub "$k" && [ -f "$k" ] && grep -Eq '(^|[[:space:]])svc-telemetry[[:space:]]*$' "$k" 2>/dev/null \
  && hit "$(fortkeep_tilde "$k") lets in a key labelled svc-telemetry, the trojanized extension's backdoor"
# Cursor names an extension's folder publisher.name-version, with the platform after it.
e="$HOME/.cursor/extensions"
if pub "$e" && [ -d "$e" ]; then
  for x in "$e"/*; do
    case "$(printf '%s' "${x##*/}" | tr '[:upper:]' '[:lower:]')" in
      anthropic.claude-code-2.1.31[23]|anthropic.claude-code-2.1.31[23]-*) hit "$(fortkeep_tilde "$x") is the trojanized Claude Code extension" ;;
    esac
  done
fi
for d in "$HOME/.node_modules" "$HOME/.node_module"; do
  there "$d" || continue
  ws=""
  for f in .npm-ws-runner.js .npm-ws.json .npm-ws.pid .npm-ws.log; do there "$d/$f" && ws="$ws $f"; done
  [ -z "$ws" ] || { hit "$(fortkeep_tilde "$d") holds the PolinRider loader's files:$ws"; continue; }
  deps="$(jq -r '[.dependencies, .devDependencies, .optionalDependencies, .peerDependencies | objects | keys[]] | .[]' "$d/package.json" 2>/dev/null)"
  if [ -d "$d/node_modules/socket.io-client" ] || { printf '%s\n' "$deps" | grep -qx axios && printf '%s\n' "$deps" | grep -qx socket.io-client; }; then
    hit "$(fortkeep_tilde "$d") holds the BeaverTail loader's packages"
  else
    seen "$(fortkeep_tilde "$d") exists without the BeaverTail packages"
  fi
done

# 4. Loader staging in the temp folders: an npm stage, staged pip packages, a dotfile named after you in base64, and
# the files the trojanized extension and MacSync's dropper leave there.
me="$(id -un)"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  for f in "$t"/.stk_* "$t"/.sys-*; do
    { [ -e "$f" ] || [ -L "$f" ]; } || continue
    if printf '%s\n' "${f##*/}" | grep -Eqx '\.stk_[0-9a-fA-F]{10}'; then hit "$(fortkeep_tilde "$f") is the trojanized Claude Code extension's file"
    elif printf '%s\n' "${f##*/}" | grep -Eqx '\.sys-[0-9]{16}'; then hit "$(fortkeep_tilde "$f") is where MacSync's dropper puts its payload"; fi
  done
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
miasma="### Node Auto-""Update Script ###"  # in pieces, as every malware marker in this repo
for f in .zshrc .zshenv .zprofile .zlogin .bashrc .bash_profile .profile .npmrc .config/fish/config.fish "$HOME"/.config/fish/conf.d/*.fish; do
  case "$f" in /*) ;; *) f="$HOME/$f" ;; esac
  { pub "$f" && [ -f "$f" ]; } || continue
  while IFS=: read -r n _; do hit "$(fortkeep_tilde "$f") line $n starts the Miasma worm's auto-update block"; done < <(grep -nF -e "$miasma" "$f" 2>/dev/null)
  while IFS=: read -r n _; do hit "$(fortkeep_tilde "$f") line $n runs MacSync's .repair-run script"; done < <(grep -nF -e .repair-run "$f" 2>/dev/null)
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
# MacSync also adds that line to the global git pre-commit and post-checkout hooks. /usr/bin/git without the Command
# Line Tools would open their install dialog, so it isn't run.
g="$(command -v git 2>/dev/null)"
if [ -n "$g" ] && ! fortkeep_needs_clt "$g"; then
  hp="$("$g" config --global --get core.hooksPath 2>/dev/null)"; rc=$?
  [ "$rc" -le 1 ] || seen "your global git config couldn't be read, so its hooks weren't looked at"
  case "$hp" in '~'/*) hp="$HOME/${hp#\~/}" ;; esac
  for h in pre-commit post-checkout; do
    f="$hp/$h"
    [ -n "$hp" ] && pub "$f" && [ -f "$f" ] && grep -qF .repair-run "$f" 2>/dev/null && hit "$(fortkeep_tilde "$f") runs MacSync's .repair-run script"
  done
fi

# 6. Scheduled jobs whose command runs inline code or a loader staged in a temp folder.
sus() {  # reads commands, one per line; prints the number of each that runs inline code or a staged loader
  FORTKEEP_TMPS="$tmps" /usr/bin/perl -ne '
    BEGIN { our $re = join "|", (map { quotemeta($_) . q{/\.(npm|pip)\b} } grep { length } split /\n/, $ENV{FORTKEEP_TMPS}), q{/\.node_modules?\b} }
    our $re; print "$.\n" if "$_ " =~ /(node|python[0-9.]*)\s+-[ce]\s/i || /$re/'
}
if ct="$(crontab -l 2>/dev/null)"; then
  body="$(printf '%s\n' "$ct" | sed 's/^[[:space:]]*#.*//')"
  # A download run as in the start-up files, or GhostAction's marker after one (in pieces, as every malware marker here).
  fl=" $(printf '%s\n' "$body" | grep -nE "$fetch_run|$decode_run|#gh""c2" | cut -d: -f1 | tr '\n' ' ')"
  for n in $fl; do hit "your crontab line $n runs downloaded code"; done
  for n in $(printf '%s\n' "$body" | sus); do
    case "$fl" in *" $n "*) ;; *) hit "your crontab line $n runs inline code or a staged loader" ;; esac
  done
fi
apple=0
for d in "$HOME/Library/LaunchAgents" "$(fortkeep_path /Library/LaunchAgents)" "$(fortkeep_path /Library/LaunchDaemons)"; do
  pub "$d" || continue
  for p in "$d"/*.plist; do
    [ -f "$p" ] || continue
    c="$(plutil -extract Program raw -o - "$p" 2>/dev/null) $(plutil -extract ProgramArguments json -o - "$p" 2>/dev/null | jq -r 'join(" ")' 2>/dev/null)"
    [ -z "$(printf '%s\n' "$c" | tr '\n' ' ' | sus)" ] || hit "$(fortkeep_tilde "$p") runs inline code or a staged loader"
    l="$(plutil -extract Label raw -o - "$p" 2>/dev/null)"
    case "$l" in
      com.apple.finder.agent) hit "$(fortkeep_tilde "$p") is MacSync's LaunchAgent, labelled com.apple.finder.agent" ;;
      # Old iCloud/MobileMe and Contacts sync agents that macOS itself left here; their names can hold an Apple ID.
      com.apple.CSConfigDotMacCert-*|com.apple.AddressBook.ScheduledSync.*) ;;
      # Malware borrows Apple's prefix to blend in. Counted, not named: a file name here can identify the person.
      com.apple.*) [ "$d" != "$HOME/Library/LaunchAgents" ] || apple=$((apple + 1)) ;;
    esac
  done
done
[ "$apple" -eq 0 ] || seen "$apple agent(s) in your own LaunchAgents use an Apple label, as malware does to blend in: worth a look"

# 7. Editor and app start-up files that PolinRider's second stage patches, so opening the app reruns the loader: its
# tags (in pieces, as every malware marker here), its eval(atob( payload, or a long tab run before an eval. These files
# can be megabytes: at most 32 MB of each is read. A file that can't be read, or only in part, is noted.
apps=()
for a in "$(fortkeep_path /Applications)" "$HOME/Applications"; do
  r="Contents/Resources/app"
  apps+=("$a/Visual Studio Code.app/$r/out/main.js" "$a/Visual Studio Code.app/$r/node_modules/@vscode/deviceid/dist/index.js"
    "$a/Cursor.app/$r/out/main.js" "$a/Cursor.app/$r/node_modules/@vscode/deviceid/dist/index.js"
    "$a/Antigravity.app/$r/node_modules/@vscode/deviceid/dist/index.js" "$a/GitHub Desktop.app/$r/main.js")
done
apps+=("$HOME/Library/Application Support/discord/"*/modules/discord_desktop_core/index.js)
files=()
for f in "${apps[@]}"; do pub "$f" && [ -f "$f" ] && files+=("$f"); done
if [ ${#files[@]} -gt 0 ]; then
  verdicts="$(/usr/bin/perl -e '
    my @tag = ("C25061"."7A", "C25061"."8A", "C25061"."9A", "C25062"."0A", "C26051"."1A", "RS2606"."05", "M26063"."0A", "NPM_WS"."_SHIM");
    my $re = join "|", (map { quotemeta } @tag), quotemeta("eval(atob("), q{\t{50,}eval\(};
    for my $f (@ARGV) {
      my ($h, $buf);
      unless (open($h, "<", $f) and defined read($h, $buf, 32 << 20)) { print "U\t$f\n"; next }
      if ($buf =~ /$re/) { print "H\t$f\n" } elsif (-s $f > length $buf) { print "P\t$f\n" }
    }' "${files[@]}")" || seen "the editor and app start-up files couldn't be read"
  while IFS=$'\t' read -r k f; do
    case "$k" in
      H) hit "$(fortkeep_tilde "$f") is patched by PolinRider's second stage: reinstall the app" ;;
      U) seen "$(fortkeep_tilde "$f") couldn't be read" ;;
      P) seen "$(fortkeep_tilde "$f") is over 32 MB, so only its start was read" ;;
    esac
  done <<EOF
$verdicts
EOF
fi

high="$(printf '%s' "$high" | sed '/^$/d')"; low="$(printf '%s' "$low" | sed '/^$/d')"
n="$(fortkeep_count "$high")"
if [ "$n" -gt 0 ]; then
  fortkeep_result "$ID" FAIL "$n sign(s) of live malware on this Mac" "$(fortkeep_join "$(printf '%s\n' "$high" | head -5)" '; '). Don't open new work or type passwords; type /if-red.$skipped"
else
  note="$(fortkeep_join "$low" '; ')$skipped"
  fortkeep_result "$ID" PASS "No live malware process, C2 connection or known backdoor file" "${note# }"
fi
