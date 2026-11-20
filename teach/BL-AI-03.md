# BL-AI-03 · The agent can't edit its own controls

**Why:** Every control above lives in files your own user can write. An agent that can edit `~/.zshrc`, its own `settings.json` or the guard script can switch them off, and a convincing README can ask it to.

**Real attack:** In August 2026 the ChainDrop worm spread through npm packages and wrote a hook into repositories' `.claude/settings.json` (and a VS Code task), so its code runs again each time someone starts Claude Code or opens the project. ([source](https://www.pillar.security/blog/chaindrop-when-opening-a-repository-becomes-execution), [source](https://zscaler.com/blogs/security-research/tracking-shai-hulud-inside-chaindrop-npm-worm))

**Check it yourself:** open your Claude Code `settings.json` and look under `permissions.deny` for `Edit(…)` entries covering that file, your shell start-up files and the guard script. For Codex, ask it to edit `~/.codex/config.toml`: a hook must refuse.

**How to fix:** add to `permissions.deny` in your Claude Code `settings.json`: `"Edit(~/.zshrc)"`, `"Edit(~/.zprofile)"`, `"Edit(~/.zshenv)"`, `"Edit(~/.zlogin)"`, `"Edit(~/.bashrc)"`, `"Edit(~/.bash_profile)"` (each one only if that file exists), `"Edit(/settings.json)"` (the file itself), one for the guard script, and `"Edit(~/.config/fortkeep/**)"` if you have `~/.config/fortkeep/path-front.sh` (the file that puts the Safe Chain shims first, from BL-SC-02). Use only `Edit(…)` rules: they cover every file-editing tool. Codex has no deny rules: there, the guard registered in `~/.codex/hooks.json` for its file edits (`apply_patch`, see BL-AI-02) must refuse an edit to `hooks.json` itself, `config.toml`, its rules files, the guard script and your shell start-up files. Never accept a security baseline from an agent.

**What the agent is doing:** reading your Claude Code deny rules and matching them against the files that need protecting, and, for Codex, sending its file-edit hook a test edit of each of those files (never writing it) to see that the hook refuses.
