#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
. "$(dirname "$0")/../lib/editors.sh"
. "$(dirname "$0")/../lib/agents.sh"
ID=GD-AI-02
# Claude Code's guard is BL-AI-02, as is the Codex hooks.json; this is the rest of each agent's own mechanism.
n=0; good=0; names=""; bad=""; undecided=""; priv=""
installed() { n=$((n + 1)); names="$names, $1"; }
hp="$(cd "$HOME" && pwd -P)"
node=(npm npx pnpm pnpx yarn corepack bun bunx); py=(pip pip3 uv uvx poetry pipx pdm)
# Home folders that hold package managers: each private one is left out, and said so, once.
nvm=1; bun=1; lbin=1
fortkeep_is_private "$HOME/.nvm" && nvm=""; fortkeep_is_private "$HOME/.bun" && bun=""; fortkeep_is_private "$HOME/.local/bin" && lbin=""
pm_paths() {  # every package manager the agent could run by full path, past the Safe Chain shims
  local d x c=() ex=()
  for d in "$(fortkeep_path /opt/homebrew/bin)" "$(fortkeep_path /usr/local/bin)"; do for x in "${node[@]}" "${py[@]}"; do c+=("$d/$x"); done; done
  c+=("$(fortkeep_path /usr/bin)/pip3")
  if [ -n "$nvm" ]; then for d in "$HOME"/.nvm/versions/node/*/bin; do for x in "${node[@]}"; do c+=("$d/$x"); done; done; fi
  [ -z "$bun" ] || c+=("$HOME/.bun/bin/bun" "$HOME/.bun/bin/bunx")
  if [ -n "$lbin" ]; then for x in "${py[@]}"; do c+=("$HOME/.local/bin/$x"); done; fi
  for x in "${c[@]}"; do [ -x "$x" ] && [ ! -d "$x" ] && ex+=("$x"); done
  [ ${#ex[@]} -gt 0 ] || return 0
  paste <(printf '%s\n' "${ex[@]}") <(fortkeep_realpath "${ex[@]}") | while IFS=$'\t' read -r x d; do
    case "$d" in "$HOME"/.safe-chain/*|"$hp"/.safe-chain/*) ;; *) printf '%s\n' "$x" ;; esac
  done
}
forbidden() {  # RULES_FILE — the program(s) each forbidden prefix_rule blocks outright
  # Only a one-element pattern (a path, or a list of alternative paths) blocks every use of the program:
  # [path, "install"] blocks only `path install`, so `path run` or `path dlx` still go through.
  fortkeep_strip_hash_comments "$1" | perl -0777 -ne '
    my $s = qr/"(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27/;
    while (/\bprefix_rule\s*\(((?:$s|[^()"\x27]|\((?1)\))*)\)/g) {
      my $b = $1;
      next unless $b =~ /\bdecision\s*=\s*["\x27]forbidden["\x27]/;
      next unless $b =~ /(?:^\s*|\bpattern\s*=\s*)\[\s*(\[(?:$s|[\s,])*\]|$s)\s*,?\s*\]/;
      my $f = $1;
      while ($f =~ /"((?:\\.|[^"\\])*)"|\x27((?:\\.|[^\x27\\])*)\x27/g) { print defined $1 ? $1 : $2, "\n" }
    }'
}
if fortkeep_real_cmd codex >/dev/null; then
  installed Codex
  if fortkeep_is_private "$HOME/.codex" || fortkeep_is_private "$HOME/.codex/rules"; then undecided="$undecided Codex"; priv=" (a private folder was excluded)"
  else
    rules=""; unread=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ -r "$f" ]; then rules="$rules"$'\n'"$(forbidden "$f")"; else unread=1; fi
    done <<EOT
$(fortkeep_codex_rules)
EOT
    [ -n "$nvm" ] && [ -n "$bun" ] && [ -n "$lbin" ] || priv=" (a private folder was excluded)"
    miss="$(pm_paths | grep -vxF -f <(printf '%s\n' "$rules") | while IFS= read -r p; do fortkeep_tilde "$p"; done)"
    k="$(fortkeep_count "$miss")"
    if [ "$k" -gt 0 ]; then
      more=""; [ "$k" -gt 5 ] && more=" and $((k - 5)) more"
      bad="$bad Codex: $k package-manager path(s) not forbidden in ~/.codex/rules: $(fortkeep_join "$(printf '%s\n' "$miss" | head -5)" ', ')$more. Add a prefix_rule(pattern=[\"<path>\"], decision=\"forbidden\") for each."
    elif [ -n "$unread" ]; then undecided="$undecided Codex"
    else good=$((good + 1)); fi
  fi
fi
if fortkeep_real_cmd opencode >/dev/null || fortkeep_app OpenCode >/dev/null; then
  installed OpenCode
  oc="$(fortkeep_opencode_dir)"
  if fortkeep_is_private "$oc"; then undecided="$undecided OpenCode"; priv=" (a private folder was excluded)"
  elif fortkeep_opencode_plugins | { while IFS= read -r f; do grep -qsF tool.execute.before "$f" && exit 0; done; exit 1; }; then good=$((good + 1))
  else bad="$bad OpenCode: no plugin in $(fortkeep_tilde "$oc")/plugin or $(fortkeep_tilde "$oc")/plugins runs on tool.execute.before."; fi
fi
if fortkeep_app Zed "Zed Preview" >/dev/null; then
  installed Zed
  z="$(fortkeep_zed_settings)"
  deny='[.agent.tool_permissions.tools.terminal.always_deny | arrays | .[] | objects | .pattern | strings | select(length > 0)] | length > 0'
  if fortkeep_is_private "$(dirname "$z")"; then undecided="$undecided Zed"; priv=" (a private folder was excluded)"
  elif [ ! -f "$z" ]; then bad="$bad Zed: no ~/.config/zed/settings.json, so nothing under agent.tool_permissions.tools.terminal.always_deny."
  elif ! j="$(fortkeep_jsonc "$z")" || ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$j"; then undecided="$undecided Zed"
  elif jq -e "$deny" >/dev/null <<<"$j"; then good=$((good + 1))
  else bad="$bad Zed: agent.tool_permissions.tools.terminal.always_deny has no pattern in ~/.config/zed/settings.json."; fi
fi
if [ "$n" -eq 0 ]; then fortkeep_result "$ID" NA "No Codex, OpenCode or Zed on this Mac"; exit 0; fi
ev="$good of $n coding agents (${names#, }) have their own guard"
if [ -n "$bad" ]; then fortkeep_result "$ID" FAIL "$ev" "${bad# }${undecided:+ Could not check:$undecided.}$priv"
elif [ -n "$undecided" ]; then fortkeep_result "$ID" ERROR "$ev" "Could not check:$undecided (unreadable settings or rules)$priv"
else fortkeep_result "$ID" PASS "$ev" "${priv# }"; fi
