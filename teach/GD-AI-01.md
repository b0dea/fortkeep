# GD-AI-01 · Agent control files unchanged since your baseline

**Why:** The agent controls live in ordinary files: Claude Code's settings, plugins and hook scripts, Codex rules, OpenCode's config and plugins, Zed's settings, Cursor's hooks, the Safe Chain shims, the npm, Yarn, pnpm, Bun, pip and uv config files, your shell start-up files and `~/.gitconfig`. Deny rules stop an agent editing them, but not a payload that runs as you. A fingerprint (SHA-256 hash) of each file shows any change since you last looked.

**Real attack:** In August 2025 malicious versions of the Nx build tool ran an npm `postinstall` script that stole credentials and added a `sudo shutdown -h 0` line to `~/.zshrc` and `~/.bashrc`, so every new Terminal window ran the attacker's command. The changed hash of each file shows that edit ([source](https://github.com/nrwl/nx/security/advisories/GHSA-cxm3-wv7p-598c)).

**Check it yourself:** `shasum -a 256 ~/.zshrc ~/.gitconfig` and compare with the hashes in `~/.config/devward/baseline/control-files.txt`. For Claude Code's own `settings.json`, only what steers the agent counts (hooks, permissions, `disableAllHooks`, enabled plugins, `env`, and the keys that run a command: `statusLine`, `apiKeyHelper`, `awsAuthRefresh`, `awsCredentialExport`, `otelHeadersHelper`), and of `~/.claude.json` only its `mcpServers`, because the rest changes for unrelated reasons.

**How to fix:** look at what changed in each file listed. If you made the change (or an update did), open the Terminal app, `cd` to this repo, and run `checks/baseline.sh accept`: it shows every changed, added or removed file and asks you to type `accept`. If you didn't, undo the change and type `/if-red`. The agent can't accept a baseline for you, on purpose.

**What the agent is doing:** hashing the agent control files and listing, by path, the ones that differ from your baseline. Private folders are skipped.
