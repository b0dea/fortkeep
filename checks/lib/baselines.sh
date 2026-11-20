#!/bin/bash
# What `checks/baseline.sh accept` records and GD-RT-01 / GD-RT-02 / GD-AI-01 compare with it. Source it, don't run it.

# Accepted baselines live outside the clone, where the agent guards and the managed settings already deny every edit.
fortkeep_baseline_dir() { printf '%s\n' "$HOME/.config/fortkeep/baseline"; }

fortkeep_plain_store() {  # DIR [FILE...] — true when DIR is absent or a real folder, and each FILE in it absent or a plain file
  local d="$1" f
  shift
  [ ! -L "$d" ] && { [ ! -e "$d" ] || [ -d "$d" ]; } || return 1
  for f in "$@"; do [ ! -L "$d/$f" ] && { [ ! -e "$d/$f" ] || [ -f "$d/$f" ]; } || return 1; done
}

fortkeep_baseline_safe() {  # true when the baseline folder and its parent are absent or real folders, and each baseline absent or a plain file
  local d; d="$(fortkeep_baseline_dir)"
  fortkeep_plain_store "${d%/*}" && fortkeep_plain_store "$d" knockknock.json listeners.txt control-files.txt
}

fortkeep_baseline_ready() {  # ID FILE WHAT [NOTE_END] — true when FILE is an accepted baseline that can be read; else prints the FAIL or ERROR
  if ! fortkeep_baseline_safe; then
    fortkeep_result "$1" ERROR "Your baselines aren't plain files in a plain folder" "$(fortkeep_tilde "$(fortkeep_baseline_dir)") or a file in it is a symlink or not a file: look at it before you accept again${4:-}"
  elif [ ! -f "$2" ]; then
    fortkeep_result "$1" FAIL "No accepted baseline yet" "Review $3, then run checks/baseline.sh accept yourself in the Terminal app${4:-}"
  elif [ ! -r "$2" ]; then
    fortkeep_result "$1" ERROR "Could not read your baseline" "$(fortkeep_tilde "$2") is not readable${4:-}"
  else return 0; fi
  return 1
}

fortkeep_baseline_new() {  # BASEFILE CURRENT — the lines of CURRENT that BASEFILE doesn't have, sorted; blank lines never count
  LC_ALL=C comm -13 <(sed '/^$/d' "$1" | LC_ALL=C sort -u) <(printf '%s\n' "$2" | sed '/^$/d' | LC_ALL=C sort -u)
}

fortkeep_knockknock_paths() { jq -r '[.. | objects | .path? | strings] | unique[]' "$1" 2>/dev/null; }  # SCAN_JSON — every item's path, once

# fortkeep_listen_sockets — "ADDRESS<TAB>PORT<TAB>PROGRAM" per TCP socket listening on an address other than loopback
# (127.*, ::1, anything on lo0). netstat -anv lists every process's sockets without root (lsof only your own), each
# with its process:pid, or (macOS before 15, and 15.8 again) only a pid column, named from ps, which also lists every
# process without root. With neither column it returns non-zero.
fortkeep_listen_sockets() {
  local out ps=""
  out="$(netstat -anv -p tcp 2>/dev/null)" || return 1
  case " $(printf '%s\n' "$out" | grep '^Proto' | tr -s ' \t' '  ') " in
    *' process:pid '*) ;;
    *' pid '*) ps="$(ps -axo pid=,ucomm= 2>/dev/null)" || return 1 ;;
    *) return 1 ;;
  esac
  printf '%s\n' "$out" | FORTKEEP_PS="$ps" /usr/bin/perl -ne '
    BEGIN { our %n = map { /^\s*(\d+)\s+(.*?)\s*$/ ? ($1, $2) : () } split /\n/, $ENV{FORTKEEP_PS} }
    our (%n, $pi);
    # The header splits "Local Address" and "Foreign Address" into two words each; a LISTEN row has one each.
    if (/^Proto/) { my @h = split; ($pi) = grep { $h[$_] eq "pid" } 0..$#h; $pi -= 2 if defined $pi; next }
    my @f = split; next unless @f > 5 && $f[0] =~ /^tcp/ && $f[5] eq "LISTEN";
    my ($addr, $port) = $f[3] =~ /^(.*)\.([^.]*)$/ or next;
    next if $addr =~ /^127\./ || $addr eq "::1" || $addr =~ /%lo0$/;
    my $name;
    if (defined $pi) { $name = $n{$f[$pi]} if defined $f[$pi] && $f[$pi] =~ /^\d+$/ }
    else { ($name) = /LISTEN(?:\s+\d+)*\s+(.+?):\d+\s/ }
    $name = "unknown" unless defined $name && length $name;
    $name =~ s/[\x00-\x1f\x7f]//g;  # names come from the Mac being checked: no control characters (tabs included)
    print "$addr\t$port\t$name\n";'
}

# fortkeep_listeners — the programs listening beyond loopback, one name per line, each once. Keyed by program name, not
# port: Tailscale, AirPlay and dev servers pick a new port each time.
fortkeep_listeners() {
  local s
  s="$(fortkeep_listen_sockets)" || return 1
  printf '%s\n' "$s" | cut -f3 | sed '/^$/d' | LC_ALL=C sort -u
}

# fortkeep_control_files — the files that enforce the agent controls, "KIND<TAB>PATH" each once, then a "!skipped" line
# when a private folder was left out. KIND is claude for a personal Claude settings file, mcp for a Claude state
# file (~/.claude.json) whose user-scope MCP servers count, else file.
fortkeep_control_files() {
  local m d s r oc scan settings="" roots=""
  m="$(fortkeep_managed_settings)"; oc="$(fortkeep_opencode_dir)"
  scan="$(fortkeep_claude_scan)"
  while IFS= read -r d; do
    case "$d" in ''|'!skipped') continue ;; esac
    for s in "$d/settings.json" "$d/settings.local.json" "$d/plugins/installed_plugins.json"; do
      [ -f "$s" ] && settings="$settings$s"$'\n'
    done
    roots="$roots$(fortkeep_plugin_roots "$d")"$'\n'
  done <<EOF
$scan
EOF
  {
    case "$scan" in *'!skipped'*) printf '!skipped\n' ;; esac
    [ -f "$m" ] && printf 'file\t%s\n' "$m"
    printf '%s' "$settings" | while IFS= read -r s; do
      case "$s" in */installed_plugins.json) printf 'file\t%s\n' "$s" ;; *) printf 'claude\t%s\n' "$s" ;; esac
    done
    fortkeep_claude_states | awk '{ print "mcp\t" $0 }'
    # Every hook script the managed and personal settings run, for any event, and each enabled plugin's.
    { [ -f "$m" ] && printf '%s\n' "$m"; printf '%s' "$settings" | grep -v '/installed_plugins\.json$'; } | while IFS= read -r s; do
      fortkeep_hook_scripts "$s"
    done | awk '{ print "file\t" $0 }'
    printf '%s' "$roots" | while IFS= read -r r; do
      [ -n "$r" ] || continue
      if fortkeep_is_private "$r"; then printf '!skipped\n'; continue; fi  # a private plugin folder is never opened
      [ -f "$r/hooks/hooks.json" ] || continue
      printf 'file\t%s\n' "$r/hooks/hooks.json"
      FORTKEEP_PLUGIN_ROOT="$r" fortkeep_hook_scripts "$r/hooks/hooks.json" | awk '{ print "file\t" $0 }'
    done
    {
      printf '%s\n' "$HOME/.codex/hooks.json" "$(fortkeep_path /etc/codex/requirements.toml)" "$oc/opencode.json" "$oc/opencode.jsonc" \
        "$(fortkeep_zed_settings)" "$HOME/.cursor/hooks.json" "$HOME/.safe-chain/bin/safe-chain" \
        "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.zshrc" "$HOME/.zlogin" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" \
        "$HOME/.gitconfig" "$HOME/.config/fortkeep/path-front.sh" "$HOME/.local/bin/git-scan-new-files" \
        "$HOME/.npmrc" "$HOME/.yarnrc" "$HOME/.yarnrc.yml" "$HOME/Library/Preferences/pnpm/rc" "$HOME/.bunfig.toml" \
        "$HOME/.pip/pip.conf" "$HOME/.config/pip/pip.conf" "$HOME/Library/Application Support/pip/pip.conf" "$HOME/.config/uv/uv.toml" \
        "$HOME/.safe-chain/shims/"*
      fortkeep_codex_rules; fortkeep_opencode_plugins
    } | while IFS= read -r s; do [ -f "$s" ] && printf 'file\t%s\n' "$s"; done
  } | awk '!s[$0]++' | while IFS=$'\t' read -r kind s; do
    if [ "$kind" = '!skipped' ] || fortkeep_is_private "$s"; then printf '!skipped\n'; else printf '%s\t%s\n' "$kind" "$s"; fi
  done | awk '$0 != "!skipped" { print; next } { skipped = 1 } END { if (skipped) print "!skipped" }'
  return 0
}

# fortkeep_control_hashes — reads fortkeep_control_files' lines; "PATH<TAB>KIND<TAB>SHA256" per control file, sorted, the hash
# "unreadable" when the file can't be read. Of a personal Claude settings file only what steers the agent counts
# (hooks, permissions, disableAllHooks, enabled plugins, env, and the keys that run a command); of ~/.claude.json
# only its user-scope mcpServers: the rest of each changes for unrelated reasons.
fortkeep_control_hashes() {
  local list kind f h j plain=()
  list="$(sed '/^!skipped$/d')"
  while IFS=$'\t' read -r kind f; do [ "$kind" = file ] && plain+=("$f"); done <<EOF
$list
EOF
  {
    printf '%s\n' "$list" | while IFS=$'\t' read -r kind f; do
      # The command-running keys join only when set, so a baseline taken before they counted still matches.
      case "$kind" in
        claude) q='{hooks, permissions, disableAllHooks, enabledPlugins, env} + with_entries(select(.key
          | IN("statusLine", "apiKeyHelper", "awsAuthRefresh", "awsCredentialExport", "otelHeadersHelper")))' ;;
        mcp) q='.mcpServers' ;;
        *) continue ;;
      esac
      { j="$(jq -cS "$q" "$f" 2>/dev/null)" && h="$(printf '%s\n' "$j" | shasum -a 256)"; } || h=unreadable
      printf '%s\t%s\t%s\n' "$f" "$kind" "${h%% *}"
    done
    # One shasum for every plain file, joined back by path: shasum leaves out a file it can't read, and marks
    # a name with a backslash in it by a leading backslash, doubling the one in the name. One stream, the hashes
    # then a "-" line then the paths: with two files, an empty hash list would make awk take the paths for hashes.
    [ ${#plain[@]} -eq 0 ] || { shasum -a 256 -- "${plain[@]}" 2>/dev/null; printf -- '-\n'; printf '%s\n' "${plain[@]}"; } \
      | awk '!paths && $0 == "-" { paths = 1; next }
        !paths { e = substr($0, 1, 1) == "\\"; h = substr($0, 1 + e, 64); p = substr($0, 67 + e)
          if (e) gsub(/\\\\/, "\\", p); hash[p] = h; next }
        { print $0 "\tfile\t" (($0 in hash) ? hash[$0] : "unreadable") }'
  } | LC_ALL=C sort
}

fortkeep_control_label() {  # PATH KIND — how a control file is named to the person
  case "$2" in
    claude) printf '%s (what steers the agent)\n' "$1" ;;
    mcp) printf '%s (its MCP servers)\n' "$1" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# fortkeep_control_diff BASELINE CURRENT — "changed|added|removed<TAB>PATH<TAB>KIND" for each difference between two hash lists.
fortkeep_control_diff() {
  local p k h base
  # A folder made private since the baseline is left out, not reported as removed.
  base="$(printf '%s\n' "$1" | while IFS=$'\t' read -r p k h; do
    [ -n "$p" ] && ! fortkeep_is_private "$p" && printf '%s\t%s\t%s\n' "$p" "$k" "$h"; done)"
  awk -F'\t' 'NR == FNR { if ($1 != "") b[$1 FS $2] = $3; next }
    $1 == "" { next }
    { k = $1 FS $2; seen[k] = 1; if (!(k in b)) print "added\t" k; else if (b[k] != $3) print "changed\t" k }
    END { for (k in b) if (!(k in seen)) print "removed\t" k }' <(printf '%s\n' "$base") <(printf '%s\n' "$2") | LC_ALL=C sort -t$'\t' -k2
}

fortkeep_sweep_seconds() {  # COUNT [weekly] — seconds the repo sweep gets for COUNT repos, npm installs and extension
  # folders: about two each (a second or so is usual), never under 140, and at most 6 minutes in a normal run, which
  # an agent waits for. The weekly run gets three times that.
  local t=$(( 15 + 2 * $1 ))
  [ "$t" -ge 140 ] || t=140
  [ "$t" -le 360 ] || t=360
  [ -z "${2:-}" ] || t=$(( t * 3 ))
  printf '%s\n' "$t"
}
