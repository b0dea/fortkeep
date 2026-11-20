load helpers

# The wiring that lets Claude Code, Codex and OpenCode all run the same skills and guards (docs/agents.md).
C="$BATS_TEST_DIRNAME/../.codex/hooks.json"
scripts() {  # EVENT [MATCHER] — the hook scripts Codex runs for it, by file name
  jq -r --arg e "$1" --arg m "${2:-}" '.hooks[$e][] | select(($m == "") or (.matcher == $m)) | .hooks[].command' "$C" \
    | sed -n 's#.*/\.claude/hooks/\([a-z-]*\.sh\)$#\1#p' | sort | paste -sd' ' -
}

@test "codex: every hook command runs an existing, executable script from .claude/hooks" {
  jq -e '.hooks | type == "object"' "$C" >/dev/null
  jq -r '.hooks[][] | .hooks[].command' "$C" | while IFS= read -r c; do
    [[ "$c" == '"$(git rev-parse --show-toplevel)"/.claude/hooks/'* ]]
    [ -x "$REPO/.claude/hooks/${c##*/}" ]
  done
}
@test "codex: the same guard as Claude Code for every tool, plus the typed approval" {
  [ "$(scripts SessionStart)" = "session-start.sh" ]
  [ "$(scripts PreToolUse)" = "guard.sh" ]
  [ "$(jq '[.hooks.PreToolUse[] | select(has("matcher"))] | length' "$C")" -eq 0 ]  # no matcher: every tool
  [ "$(scripts UserPromptSubmit)" = "approval-recorder.sh" ]
}
@test "codex: its hosted web search, which no hook sees, is off in this folder" {
  [ "$(sed -n 's/^web_search *= *"\(.*\)"$/\1/p' "$REPO/.codex/config.toml")" = disabled ]
}
@test "claude code: one guard sees every tool, so a tool with no guard is refused in a person's session" {
  S="$REPO/.claude/settings.json"
  [ "$(jq -c '[.hooks.PreToolUse[] | {matcher, c: [.hooks[].command]}]' "$S")" = '[{"matcher":"*","c":["\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard.sh"]}]' ]
  [ "$(jq -r '.hooks.PostToolUse[] | select(.matcher == "AskUserQuestion") | .hooks[].command' "$S")" = '"$CLAUDE_PROJECT_DIR"/.claude/hooks/approval-recorder.sh' ]
}
@test "codex and opencode: sudo is refused and every fix script, in its one spelling, needs a confirmation" {
  rules="$REPO/.codex/rules/fortkeep.rules"
  grep -q 'prefix_rule(pattern=\["sudo"\], decision="forbidden"' "$rules"
  for f in "$REPO"/fixes/macos/*.sh; do
    grep -qF "prefix_rule(pattern=[\"fixes/macos/${f##*/}\"], decision=\"prompt\"" "$rules"
  done
  [ "$(jq -r '.permission.bash["fixes/macos/*"]' "$REPO/opencode.json")" = ask ]
  [ "$(jq -r '.permission.bash | keys | join(" ")' "$REPO/opencode.json")" = "fixes/macos/* sudo *" ]  # no other spelling
  [ "$(jq -r '.permission.bash["sudo *"]' "$REPO/opencode.json")" = deny ]
}
@test "skills live in .agents/skills, internal to a fortkeep checkout; .claude/skills points there; names fit every agent" {
  [ "$(readlink "$REPO/.claude/skills")" = ../.agents/skills ]
  n=0
  for f in "$REPO"/.agents/skills/*/SKILL.md; do
    d="$(basename "$(dirname "$f")")"
    name="$(sed -n 's/^name: //p' "$f" | head -1)"; desc="$(sed -n 's/^description: //p' "$f" | head -1)"
    [ "$name" = "$d" ]                                           # OpenCode: the name is the folder's name
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]
    [ -n "$desc" ] && [ "${#desc}" -le 1024 ]
    grep -qx '  internal: "true"' "$f"                          # skills.sh lists it only with INSTALL_INTERNAL_SKILLS=1
    n=$((n + 1))
  done
  [ "$n" -eq 5 ]
}
@test "AGENTS.md is the instructions; CLAUDE.md only imports it" {
  [ -f "$REPO/AGENTS.md" ] && [ ! -L "$REPO/AGENTS.md" ]
  [ "$(cat "$REPO/CLAUDE.md")" = "@AGENTS.md" ]
}
