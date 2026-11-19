# What devward touches

Everything devward reads, writes and sends over the network, and what a run may ask of macOS. It is for anyone
deciding whether to run it, and for anyone removing it.

## What it reads

The checks only read. Each lesson's "What the agent is doing" line (`teach/<ID>.md`) says exactly what its check
looks at. In short:

- **macOS settings:** FileVault, firewall, Gatekeeper, System Integrity Protection, software update preferences,
  sharing services, screen lock, `/etc/pam.d/sudo_local`, launchd's user PATH, and the DNS servers in use.
- **Installed apps and running programs:** names and versions of security tools (`/Applications`,
  `~/Applications`), the system extensions list, and the running processes' names, terminals, ages and working
  folders. GD-RT-03 also lists your own network connections, and reads the process list's command lines only to
  recognise a hidden node or python loader, never reporting them. Of the open apps' environment, only `PATH` is read.
- **Your start-up and tool configuration:** shell start-up files (`~/.zshrc`, `~/.zprofile`, `~/.zshenv`,
  `~/.zlogin`, `~/.bashrc`, `~/.bash_profile`, `~/.profile`), `~/.gitconfig` and its hooks, the npm, Yarn, pnpm,
  Bun, pip and uv config files, Safe Chain's files in `~/.safe-chain`, `~/.ssh/config`, and the key files in `~/.ssh`, which
  `ssh-keygen` tries to open with an empty passphrase to see whether each has one; no key is printed or kept.
- **Coding agents' settings:** Claude Code (`~/.claude`, `~/.claude.json`'s MCP servers, the managed settings in
  `/Library/Application Support/ClaudeCode`), Codex (`~/.codex`, `/etc/codex/requirements.toml`), OpenCode, Zed,
  Cursor and the VS Code family's settings. The guards are sent test commands; nothing they would run is run.
- **Browsers:** each Chrome-family and Firefox profile's settings file, its extension list, and the number of
  passwords saved in it (a count; no password is opened).
- **Folders that may hold leaked keys or cloned repos:** the top of your home folder, and `~/Desktop`,
  `~/Documents` and `~/Downloads` (BL-SE-03, GD-RC-01), plus your code folders (GD-RC-01 lists them).
- **A folder you ask about:** `/scan` and `devward scan` read the git repos in the one folder you name: their
  files (tracked or not, except node_modules), git hooks and commit history. Nothing from them runs.
- **devward's own state:** everything listed under "What it writes" below.

Folders in `private-paths` are never read, listed or searched, by the checks or by the agent. When one is skipped,
the result says only "a private folder was excluded".

## What it writes

The installer (`install.sh`, or Homebrew's `devward` on first run) puts the devward folder at
`~/.local/share/devward`, links `~/.local/bin/devward` to its command when `~/.local/bin` exists, and records the
release it installed under `~/.config/devward/`. A review (`checks/run.sh`) writes only inside devward's own folders:

| Where | What |
|---|---|
| `reports/` in the devward folder | settings (`config.json`), each run's `results.json`, the `latest` link, the posture summary, the KnockKnock scan, `weekly-last`, and `change-log.md` with every change a fix made |
| `reports/.approvals/` | the agent hooks' record of each `Apply`, `Undo` or `Accept` answer; never touched by hand |
| `accepted.json` and `private-paths` in the devward folder | your accepted decisions and your private folders |
| `~/.config/devward/` | accepted baselines (`baseline/`), the repo sweep's last result, and which signed release this Mac last ran and trusts |
| `~/.local/state/devward/backups/` | a copy of each file a fix changed, so it can be undone |

A fix writes only after you answer `Apply <ID>`, and logs what it did in `reports/change-log.md` with its undo:

| Fix | What it writes |
|---|---|
| BL-SC-02 | `~/.config/devward/path-front.sh`, and one marked line in `~/.zshenv`, `~/.zshrc`, `~/.zlogin` and your bash start-up files |
| BL-RC-01 | `"task.allowAutomaticTasks": "off"` in each VS Code-family editor's `settings.json` |
| BL-RC-02 | the scan hook at `~/.local/bin/git-scan-new-files`, hook entries in `~/.gitconfig`; the hook logs to `~/.local/var/log/git-scan.log` |
| BL-SE-06 | a gitleaks pre-commit hook entry in `~/.gitconfig` |
| BL-AU-02 | the weekly LaunchAgent `~/Library/LaunchAgents/io.github.b0dea.devward.weekly.plist`, logging to `~/Library/Logs/devward-weekly.log` |

Admin changes are typed by you in the Terminal app, never by the agent. The lessons give them: for example the
root-owned agent guard in `/usr/local/lib/safe-chain-agent/`, Claude Code's managed settings, Codex's
`/etc/codex/requirements.toml`, `/etc/pam.d/sudo_local`, launchd's user PATH, the firewall and Gatekeeper.

## Removing devward

`devward uninstall` does it in order, and never runs `sudo` or deletes the devward folder itself:

1. It refuses while a fix that installed something is still applied: the scan hook, the gitleaks hook, the Safe
   Chain start-up lines or the weekly job. Undo each in your agent first (`devward agent`, then ask it to undo the
   fix and answer `Undo <ID>`), so the backup puts your files back. The editor setting from BL-RC-01 may stay: it
   works without devward.
2. It prints the admin changes below. They don't need devward and keep protecting the Mac without it. To remove
   them anyway, type them yourself in the Terminal app, and only those you made from a devward lesson, not ones your
   organisation installed:

   <!-- devward-uninstall-admin:start -->
   ```sh
   sudo rm -f /usr/local/lib/safe-chain-agent/agent-guard.sh "/Library/Application Support/ClaudeCode/managed-settings.json"
   sudo rm -f /etc/codex/requirements.toml
   sudo launchctl config user path "/usr/bin:/bin:/usr/sbin:/sbin"   # then restart the Mac
   sudo -k
   ```
   <!-- devward-uninstall-admin:end -->

3. After you answer `yes`, it removes `~/.local/state/devward` (fix backups), `~/.config/devward` (baselines and
   release records) and the `~/.local/bin/devward` link the installer made.
4. You delete the devward folder yourself (by default `~/.local/share/devward`), and run `brew uninstall devward` if
   you installed it with Homebrew. The logs `~/.local/var/log/git-scan.log` and `~/Library/Logs/devward-weekly.log`
   are yours to keep or delete.

## What it sends over the network

Checks are meant not to use the network, so a run says nothing about you to anyone. These are the exceptions:

- **BL-BR-06 (DNS filtering):** when the DNS servers aren't on its list of known filtering services, one DNS
  lookup of `malware.testcategory.com`, Cloudflare's published malware test name; only if that gets no answer at
  all, one lookup of `example.com` to tell a block from no network.
- **BL-SC-01 (Safe Chain installed):** runs Safe Chain's own `safe-chain-verify`, then asks npm, through Safe
  Chain, for Safe Chain's harmless test package in an empty temporary folder. That reaches the npm registry and
  Safe Chain's malware feed, as any install through Safe Chain does.
- **OV-TP-02 (only with the TLS-proxy set-up):** runs `safe-chain-verify` from a non-interactive shell, to see
  that it finishes behind your employer's proxy.
- **The installer:** clones devward from GitHub (Homebrew also downloads the release's source archive).
- **`checks/update.sh` (`devward update`):** fetches the release tags from devward's git remote, only when you run
  it.
- **The weekly check (`checks/weekly.sh`):** `brew update`, then `brew vulns`, which use Homebrew's own servers.
  When KnockKnock is installed, its scan runs with VirusTotal turned off (`-skipVT`).

Nothing else is sent: no telemetry, no results, no file contents.

## macOS privacy prompts

The first run may make macOS ask whether your terminal or agent app may open the **Desktop**, **Documents** and
**Downloads** folders. BL-SE-03 looks there for leaked key files, and GD-RC-01 for cloned repos. Allowing it lets
those checks finish. If you decline, they report ERROR for that folder, and nothing else changes. You can change
your answer later in System Settings → Privacy & Security → Files and Folders.

## How long a run takes

Not measured on a reference Mac yet. The checks run one after another, each stopped at its own time limit (the
`timeout` of each control in `controls/controls.json`, or the default in `checks/run.sh`), and the run prints one
progress line per check. Expect minutes rather than seconds. The slowest check, the repo sweep (GD-RC-01), runs in
the weekly check; other reviews show its stored result.

## "Stopped from outside"

A result that says "Something outside devward stopped this check" means another program ended the check before it
could answer. It is usually a security tool (antivirus or endpoint protection) mistaking a read-only check for
malware. It is not a sign that the Mac is unsafe, and that check simply has no answer this time.

What to do: on a work Mac, ask your IT or security team to add an exclusion for the devward folder. On your own Mac,
look at the security tool's log or quarantine for devward's check, and allow it there. Never turn the security tool
off to make the check pass.
