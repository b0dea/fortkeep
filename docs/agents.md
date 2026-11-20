# Agents

fortkeep runs in Claude Code, Codex and OpenCode. All three read the same instructions and skills and run the
same guard scripts; only the wiring differs.

| | Claude Code | Codex | OpenCode |
|---|---|---|---|
| Instructions | `CLAUDE.md` (imports `AGENTS.md`) | `AGENTS.md` | `AGENTS.md` |
| Skills | `.claude/skills` → `.agents/skills` | `.agents/skills` | `.agents/skills` and `.claude/skills` (same files) |
| Start a skill | `/posture` | `$posture` (or `/skills`) | `/posture` |
| Guards wired in | `.claude/settings.json` | `.codex/hooks.json`, `.codex/rules/`, `.codex/config.toml` | `.opencode/plugins/fortkeep.ts`, `opencode.json` |
| Guards start | after "trust this folder" | after trusting the folder **and** its hooks | by themselves |
| How `Apply <ID>` is given | picked in AskUserQuestion | typed as the whole message | picked in the `question` tool |

The guard scripts live in `.claude/hooks/`. Each receives the event in Claude Code's JSON shape; Codex sends that
shape natively and the OpenCode plugin translates to it.

A session the person starts is allow-listed. `guard.sh` sees every tool call (Claude Code runs it for every tool,
Codex for every local tool, the OpenCode plugin for the tools it maps). Codex's hosted web search and `write_stdin`
never reach a hook; `.codex/config.toml` turns the web search off.
- Shell: exactly one of fortkeep's own scripts with arguments of the right kind, from the repo folder, in the one
  spelling the skills use. The list is `.claude/hooks/allow-list`. Any other program, a pipe, redirection, variable,
  substitution, glob, newline or backslash is refused, and so is a character beyond ASCII, except letters and
  punctuation inside quotes in a name or reason. A fix is also refused while the agent is in bypass, auto or
  accept-edits mode, where it would run without the person's prompt.
- Read, Grep and Glob: physical paths inside this checkout, never `private-paths`, `reports/.approvals` or `.git`, plus
  this project's own scratch folder and Claude Code project folder (memory, saved tool output). A search may not start
  at a folder that holds any of those. Codex has no read tool, so `checks/show.sh <path>` prints a file under the
  same rule. The Artifact tool may publish only files these rules let it read.
- Writes (`write-guard.sh`): only this project's scratch folder and the plan folder, never memory, whose notes later
  sessions load as instructions. Nothing in the repo,
  `reports/` included: `checks/configure.sh` saves settings and `checks/run.sh` writes results. A patch is read the way
  Codex and OpenCode read it (headers trimmed of any Unicode space); a header it doesn't know is refused.
- Any other tool is refused, except the ones that touch no file and run no command: the question tool, the todo
  tools, `skill`, plan mode, Claude Code's `ToolSearch`, and Codex's plan and input tools. Web fetch and search are
  refused too: a URL or query could carry what the agent read off this Mac. The
  OpenCode plugin keeps the same set, refuses every tool it doesn't map, and checks its folder-listing tool as a
  search of that folder. Subagents and MCP tools are refused: their calls are not known to pass through the guards.

A development session (`FORTKEEP_DEV=1` and the marker `~/.config/fortkeep/dev`, see CONTRIBUTING.md) keeps the
deny-list guards, with names folded as APFS compares them (NFC, upper case, lower case, NFC), so a look-alike letter
such as `ſ` can't stand in for `s`:
- `bash-guard.sh`: no `sudo`, no download piped into a shell, no forged approvals or tampered fix runs.
- `write-guard.sh`: edits stay in the repo and the agent's own folders, never in the approval tokens or KnockKnock
  scans; a patch is checked file by file.
- `private-guard.sh` (in a person's session too): never reads, lists or searches a folder from `private-paths`, or the
  fix backups in `~/.local/state/fortkeep/backups`.

The others:
- `session-start.sh`: the opening message. It warns unless this copy is exactly a signed release with nothing changed
  (ignored files where agents load config, git hooks and local git settings that run commands count), when the
  release is older than one this Mac ran before (`~/.config/fortkeep/highest-release`), and when the agent's mode would
  skip the person's prompts. A release counts only when a key this Mac trusts signed it: the signers of the first
  release it ran, then those each newer release names (`~/.config/fortkeep/release-signers`), so a commit can't add
  its own signer. The fix library and the scripts a person runs (`checks/baseline.sh accept`,
  `checks/private.sh remove`, `checks/managed-settings.sh`, `checks/update.sh`) refuse such a copy before they source
  anything else.
- `approval-recorder.sh`: turns the person's `Apply <ID>`, `Undo <ID>`, `Accept <ID>` or `Add private folder` into a
  one-use token under `reports/.approvals`, only when it is the answer to exactly the question `checks/ask.sh` prints
  for it, and never when another agent started this one (`codex exec`, `claude -p` or `opencode run` inside a
  session). `guard.sh` refuses, in either session, a question that arrives with its answers already filled in: only
  the model could have written them. A fix script, `checks/accept.sh` or `checks/private.sh add` refuses to run without a fresh token; a
  private-folder token holds the folder its question named, and adds only that one; an accept token holds the reason
its question named, and `checks/accept.sh` records only that reason. The
  token is a guard against mistakes, not a wall: it is a file the person's own account can write. What stops an
  agent is the guards keeping it out of `reports/.approvals` and the agent asking before any fix script runs (Claude
  Code's allow-list leaves them out, `.codex/rules` and `opencode.json` set them to prompt).

## First run

**Claude Code.** Run `claude` in this folder and accept "trust this folder".

**Codex.** Run `codex` in this folder. Trust the folder, then answer the hooks prompt with "Trust all and continue"
(or review them with `/hooks`). Codex asks again whenever a hook file changes. If you continue without trusting them,
no guard runs and no approval is recorded, and only the instructions keep the agent from guarded actions: it should
say the guards are off and not run `/fix`. Don't use it that way. Keep Codex out of its read-only mode too: there
fortkeep's scripts can't make the temporary files the shell needs, so they stop rather than risk missing a private
folder.

**OpenCode.** Run `opencode` in this folder. The plugin loads by itself; on first run OpenCode also installs its plugin
library into `.opencode/` (a `.gitignore`, `package.json` and `node_modules`, ignored by git). Starting it with `--pure`
skips the plugin, though `opencode.json` still refuses `sudo` and asks before a fix. With
`OPENCODE_DISABLE_PROJECT_CONFIG` set, nothing from this repo loads, not even `AGENTS.md`: don't use it that way.

## Why Codex approvals are typed

Codex offers its question tool only in Plan mode, so in Codex the person types `Apply <ID>` (or `Accept <ID> <reason>`)
as their whole message and a `UserPromptSubmit` hook records it. The model can't write the person's message, so a typed approval is as strong as
a picked one. A message that only contains `Apply <ID>` among other words, or spans several lines, records nothing,
and neither does a message to a subagent (the model writes those; Codex marks them with `agent_id`) or to a Codex
another agent started (`codex exec` inside a Claude Code session: the hook finds two agents above it).

Codex runs the guard for every local tool, MCP tools, subagents and `view_image` included; in a person's session it
refuses MCP tools and subagents. Its hosted web search and `write_stdin` reach no hook; `.codex/config.toml` turns the
web search off (start Codex with `-c web_search=live` to use it while developing fortkeep).

## Other agents

Any agent that reads `AGENTS.md` can explain results, but without these hooks no guard runs and no approval is
recorded, so don't use it for `/fix`. The agent detection in `checks/lib/agent.sh`, which keeps `checks/baseline.sh
accept` for the person, recognises Claude Code, Codex and OpenCode.
