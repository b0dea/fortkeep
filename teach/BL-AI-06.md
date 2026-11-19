# BL-AI-06 · The agent's sandbox on (Claude Code, Codex)

**Why:** The sandbox (macOS Seatbelt) limits, at kernel level, where the agent's commands can write and which network destinations they can reach. It's a stronger fence than pattern-matching hooks. By default it doesn't stop them reading your files: to keep `~/.ssh` or `~/.aws/credentials` out of reach, add a deny rule for reading them.

**Real attack:** The ChainDrop worm of August 2026 collected SSH keys from `~/.ssh` and other credentials and sent them out. Claude Code's sandbox only lets commands reach websites you have allowed, so the sending step is blocked; reading `~/.ssh` is allowed unless you add a deny rule for it. ([source](https://zscaler.com/blogs/security-research/tracking-shai-hulud-inside-chaindrop-npm-worm), [source](https://code.claude.com/docs/en/sandboxing))

**Check it yourself:** your Claude Code `settings.json` (or the managed one) has `"sandbox": {"enabled": true}`. Codex sandboxes its commands unless `~/.codex/config.toml` sets `sandbox_mode = "danger-full-access"`.

**How to fix:** in Claude Code, add that setting, then expect breakage: `docker`, `gh`, `terraform` and `osascript` usually need exclusions, and the loop is slower. That trade-off is why this is NICE, not MUST. In Codex, remove the `danger-full-access` line (or choose `workspace-write`).

**What the agent is doing:** reading the sandbox setting in Claude Code's settings and Codex's `config.toml`.
