# BL-AI-04 · A root-owned copy of the agent controls the agent can't reach

**Why:** Every control in BL-AI-02 and BL-AI-03 lives in files your own user can write, so an agent running as you can, in principle, undo them. A copy owned by root, which managed settings make win over user and project settings, can't be changed without your admin password. Deny rules there apply even with `--dangerously-skip-permissions`.

**Real attack:** Check Point showed that a hook in a cloned repo's own `.claude/settings.json` ran a command as soon as the user accepted the trust prompt (fixed in 2025). Settings the repo or your user can write can be changed by whatever you open; Claude Code's admin-managed settings can block user, project and plugin hooks, and a repo can't switch those off. ([source](https://research.checkpoint.com/2026/rce-and-api-token-exfiltration-through-claude-code-project-files-cve-2025-59536/), [source](https://workos.com/blog/npm-worm-coding-agent-config-credentials))

**Check it yourself:** `ls -l "/Library/Application Support/ClaudeCode/managed-settings.json"` shows `root wheel`, and the file contains `"disableBypassPermissionsMode": "disable"` and a hook pointing at a script under `/usr/local/lib`. For Codex, `ls -l /etc/codex/requirements.toml` shows `root wheel`, and the file allows only `read-only` and `workspace-write`.

**How to fix:** this needs your admin password. Open the Terminal app (Applications → Utilities), go to the fortkeep folder (`cd` and a space, then the folder), and type each step on its own, pressing Return after each.

For Claude Code:
1. `t="$(mktemp -d)"` makes a temporary folder for two files.
2. `checks/managed-settings.sh guard > "$t/agent-guard.sh"` saves the guard script, taken from the signed release.
3. `checks/managed-settings.sh > "$t/managed-settings.json"` saves the settings, with a rule for every other Claude Code folder it finds (such as your `CLAUDE_CONFIG_DIR`, if you use one: type this where that is set).
4. `jq -e '.permissions.deny | length > 0' "$t/managed-settings.json"` must print `true`. If it prints anything else, or step 2 or 3 said REFUSED, stop and tell the agent what you saw.
5. `sudo mkdir -p /usr/local/lib/safe-chain-agent "/Library/Application Support/ClaudeCode"`. macOS asks for your password; nothing appears on screen while you type it, which is normal.
6. `sudo install -o root -g wheel -m 755 "$t/agent-guard.sh" /usr/local/lib/safe-chain-agent/agent-guard.sh`
7. `sudo install -o root -g wheel -m 644 "$t/managed-settings.json" "/Library/Application Support/ClaudeCode/managed-settings.json"`
8. `sudo -k`, which ends the admin session.

For Codex, which reads its root-owned rules from `/etc/codex/requirements.toml`:
1. `sudo mkdir -p /etc/codex`
2. `echo 'allowed_sandbox_modes = ["read-only", "workspace-write"]' | sudo tee /etc/codex/requirements.toml`
3. `sudo -k`

After each fortkeep update, repeat the Claude Code steps: this check compares the root-owned guard with your own copy of the same name and fails while they differ. Keep the agent autonomous: the point is a filter on what it installs and which files it touches, not approving every command. Codex's `workspace-write` mode still works on its own inside your project; only switching its sandbox off entirely (`danger-full-access`) is ruled out. Don't set `allowManagedHooksOnly` unless every hook you rely on is in the managed file. This protects against the agent, not against someone with your admin password.

**What the agent is doing:** reading the managed settings file and Codex's requirements, checking who owns them and the hook script, and comparing that script with your own copy. The agent never runs sudo.
