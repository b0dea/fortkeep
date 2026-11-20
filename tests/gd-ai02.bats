load helpers

setup() { setup_env; }
chk() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }
prog() { mkdir -p "$(dirname "$1")"; printf '#!/bin/sh\n' > "$1"; chmod +x "$1"; }  # PATH

@test "GD-AI-02 no Codex, OpenCode or Zed → NA" {
  chk GD-AI-02; [ "$(field status)" = NA ]
}
@test "GD-AI-02 Codex: each real package-manager path needs a forbidden prefix_rule; shims, comments and other decisions don't count" {
  stub codex 'exit 0'
  prog "$FORTKEEP_SYSROOT/opt/homebrew/bin/npm"
  prog "$HOME/.nvm/versions/node/v1.0.0/bin/pnpm"
  prog "$HOME/.local/bin/uv"; prog "$HOME/.local/bin/pipx"; prog "$FORTKEEP_SYSROOT/opt/homebrew/bin/pdm"
  prog "$HOME/.safe-chain/shims/npx"; mkdir -p "$FORTKEEP_SYSROOT/usr/local/bin"; ln -s "$HOME/.safe-chain/shims/npx" "$FORTKEEP_SYSROOT/usr/local/bin/npx"
  P="$HOME/.nvm/versions/node/v1.0.0/bin/pnpm"
  mkdir -p "$HOME/.codex/rules"
  cat > "$HOME/.codex/rules/guard.rules" <<EOF
prefix_rule(
    pattern = ["$FORTKEEP_SYSROOT/opt/homebrew/bin/npm"],
    decision = "forbidden",
    justification = "Skips the shims (use plain npm)",
)
# prefix_rule(pattern=["$P"], decision="forbidden")
prefix_rule(pattern=["$HOME/.local/bin/uv"], decision="prompt")
EOF
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "0 of 1 coding agents (Codex) have their own guard" ]
  [[ "$(field note)" == *"Codex: 4 package-manager path(s)"* ]]
  [[ "$(field note)" == *"~/.nvm/versions/node/v1.0.0/bin/pnpm"* ]]; [[ "$(field note)" == *"~/.local/bin/uv"* ]]
  [[ "$(field note)" == *"~/.local/bin/pipx"* ]]; [[ "$(field note)" == *"/opt/homebrew/bin/pdm"* ]]
  [[ "$(field note)" != *homebrew/bin/npm* ]]; [[ "$(field note)" != *npx* ]]
  # A second element narrows the rule to one subcommand: `uv run` or `pnpm dlx` would still go through.
  printf 'prefix_rule(pattern=[["%s", "%s", "%s", "%s"], "install"], decision="forbidden")\n' "$P" "$HOME/.local/bin/uv" \
    "$HOME/.local/bin/pipx" "$FORTKEEP_SYSROOT/opt/homebrew/bin/pdm" > "$HOME/.codex/rules/more.rules"
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Codex: 4 package-manager path(s)"* ]]
  printf 'prefix_rule(pattern=[["%s", "%s", "%s", "%s"],], decision="forbidden")\n' "$P" "$HOME/.local/bin/uv" \
    "$HOME/.local/bin/pipx" "$FORTKEEP_SYSROOT/opt/homebrew/bin/pdm" > "$HOME/.codex/rules/more.rules"
  chk GD-AI-02; [ "$(field status)" = PASS ]
}
@test "GD-AI-02 OpenCode: a plugin on tool.execute.before → PASS; none → FAIL" {
  stub opencode 'exit 0'
  O="$HOME/.config/opencode"; mkdir -p "$O/plugins"; echo 'export const P = async () => ({})' > "$O/plugins/other.ts"
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [ "$(field note)" = "OpenCode: no plugin in ~/.config/opencode/plugin or ~/.config/opencode/plugins runs on tool.execute.before." ]
  mkdir -p "$O/plugin"; echo 'export const G = async () => ({ "tool.execute.before": async () => {} })' > "$O/plugin/guard.js"
  chk GD-AI-02; [ "$(field status)" = PASS ]
}
@test "GD-AI-02 Zed: a terminal always_deny pattern in settings with comments → PASS; empty → FAIL; unreadable → ERROR" {
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Zed.app" "$HOME/.config/zed"; Z="$HOME/.config/zed/settings.json"
  cat > "$Z" <<'EOF'
// Zed settings
{
  "agent": {
    "tool_permissions": {
      "tools": {
        "terminal": {
          "always_deny": [], // "always_deny": [{ "pattern": "x" }]
        },
      },
    },
  },
}
EOF
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *always_deny* ]]
  sed -i '' 's#"always_deny": \[\],#"always_deny": [ { "pattern": "/(npm|pip3?)\\\\s+install" }, ],#' "$Z"
  chk GD-AI-02; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "1 of 1 coding agents (Zed) have their own guard" ]
  echo '{ "agent": ' > "$Z"
  chk GD-AI-02; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *Zed* ]]
}
@test "GD-AI-02 a private Codex folder → ERROR that never names it; FAIL elsewhere still wins" {
  stub codex 'exit 0'; prog "$FORTKEEP_SYSROOT/opt/homebrew/bin/npm"
  mkdir -p "$HOME/.codex/rules"; printf '%s\n' "$HOME/.codex" > "$FORTKEEP_PRIVATE_PATHS"
  chk GD-AI-02; [ "$(field status)" = ERROR ]; [[ "$(field note)" == *"a private folder was excluded"* ]]; [[ "$output" != *.codex* ]]
  mkdir -p "$FORTKEEP_SYSROOT/Applications/Zed.app"
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not check: Codex"* ]]
}
@test "GD-AI-02 a private ~/.nvm is left out and the note says so; once not private its package managers count" {
  stub codex 'exit 0'; prog "$HOME/.nvm/versions/node/v1.0.0/bin/npm"; mkdir -p "$HOME/.codex/rules"
  echo "$HOME/.nvm" > "$FORTKEEP_PRIVATE_PATHS"
  chk GD-AI-02; [ "$(field status)" = PASS ]; [ "$(field note)" = "(a private folder was excluded)" ]
  : > "$FORTKEEP_PRIVATE_PATHS"
  chk GD-AI-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"~/.nvm/versions/node/v1.0.0/bin/npm"* ]]
}
