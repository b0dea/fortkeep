# Changelog

What changed in each release, for someone deciding whether to update. Each
[GitHub release](https://github.com/b0dea/fortkeep/releases) also lists the merged pull requests.

## Unreleased: 0.1.0

The first public release.

- **What it checks.** A Mac against a practical baseline for developers: the macOS basics, protection against
  malicious npm and PyPI packages, poisoned repos and editor tasks, guards on AI coding agents, secrets lying
  around, runtime protection and browsers. A stricter gold layer and opt-in overlays sit on top. The controls are in
  `controls/`, with the reasoning in `controls/baseline-source.md`.
- **How.** Your coding agent (Claude Code, Codex or OpenCode) runs the read-only checks, explains each result in
  plain language, and fixes a gap only after you approve that one change, with a backup and an undo. Teach mode adds
  a short lesson per control.
- **Trust.** Guard hooks limit what the agent may do in your session, and copies update only to releases a
  maintainer signed. [docs/threat-model.md](docs/threat-model.md) says what that does and doesn't stop.
- **The `fortkeep` command.** Check the Mac from the Terminal without an agent (`fortkeep check`, with `--json`), read
  a control's lesson (`fortkeep explain`), scan a repo for signs it is poisoned before you open it (`fortkeep scan`, or
  `/scan` in your agent), start your agent in the right folder (`fortkeep agent`), make the posture summary, update,
  and uninstall once the fixes are undone.
- **Install.** An installer you download and check before running, pinned to one release's tag and commit, and a
  Homebrew formula in the `b0dea/tap` tap that runs the same installer on first use. Both install to
  `~/.local/share/fortkeep`.
- **A skill on skills.sh.** A read-only `fortkeep` skill for any agent session: it runs the check, explains the
  results and hands every fix to `fortkeep agent`.

Known not to work yet:

- macOS only, and only the three agents above; with any other agent nothing is guarded.
- No fixing from the Terminal: fixes need your agent's question tool (or, in Codex, your typed answer).
- Not run yet on a wide range of Macs; how long a full run takes isn't measured.
- Releases before 1.0 may tighten controls and change commands.
- The limits listed in [docs/threat-model.md](docs/threat-model.md#known-limits).
