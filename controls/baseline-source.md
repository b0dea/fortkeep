# macOS developer security setup

A practical baseline for a developer Mac in 2026. It assumes you install packages from npm and PyPI
daily, clone repos you did not write, and let AI coding agents run commands. Those three things are
how developer machines get owned today, and most of the defences below are free.

Legend: **MUST** do this week · **SHOULD** do this month · **NICE** when you get to it · **$** costs money.

---

## 0. Threat model, in one paragraph

Nobody is going to brute-force your laptop. You will be compromised by (a) a package whose latest
version was hijacked an hour ago, (b) a repository that runs code the moment you open it or
`npm install` it (North Korea-linked fake job-interview campaigns, Contagious Interview and PolinRider among
them, send developers such repos, and their stealers take browser logins, wallets and keys), (c) a web page that tells you to
paste a command into Terminal (ClickFix / AMOS stealer), or (d) an AI agent that, prompted by text in
a repo, installs or runs something it should not. Everything below is layered against those four.

---

## 1. The OS itself (all free, all MUST)

| Setting | Where | Why |
|---|---|---|
| FileVault on | System Settings → Privacy & Security | Lost laptop = lost disk, not lost data |
| Firewall on + stealth mode | Privacy & Security → Firewall | Nothing on the LAN can probe you |
| Gatekeeper left on, never `spctl --master-disable` | default | Blocks unsigned downloads |
| Automatic updates on, including security responses | General → Software Update | Most macOS exploits in the wild are already patched |
| AirPlay Receiver, Remote Login, Remote Management, File Sharing: off | General → AirDrop & Handoff / Sharing | Listening services you don't use |
| Screen lock immediately, Touch ID for sudo | Lock Screen / `/etc/pam.d/sudo_local` | |
| Browser password manager off, a password manager on (1Password, Bitwarden or Apple Passwords) | each browser | Stealers read browser stores from disk; they cannot read a locked vault |
| Remote-access tools you don't actively use (TeamViewer, AnyDesk, RustDesk) uninstalled with the vendor uninstaller | Terminal | They leave authorization plugins and privileged helpers behind — root-level persistence you'll see in every KnockKnock run |

Check them in one go: `csrutil status`, `fdesetup isactive`, `spctl --status`,
`/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode`.

---

## 2. Install-time protection for npm / PyPI (the layer that matters most)

**MUST: [Aikido Safe Chain](https://github.com/AikidoSec/safe-chain)** (free, open source).
Wraps `npm npx pnpm yarn bun pip pip3 python -m pip uv uvx poetry pipx pdm`. Two things it does:
blocks packages on Aikido's malware feed, and refuses any version published less than 48 hours ago.
The second one is the whole trick: hijacked versions are almost always yanked within hours.

Install it properly, which the installer alone does not do:

```sh
curl -fsSL https://github.com/AikidoSec/safe-chain/releases/download/<version>/install-safe-chain.sh -o /tmp/i.sh
# verify the sha256 against the README before running it
sh /tmp/i.sh          # interactive-shell aliases
sh /tmp/i.sh --ci     # PATH shims in ~/.safe-chain/shims, for scripts, IDEs and agents
```

Then make the shims win **everywhere**, not just in your terminal:

- Put `~/.safe-chain/shims` first on PATH at the **end** of `~/.zshrc` **and** `~/.zprofile`
  (login shells like `zsh -lc`, which Codex uses, never read `.zshrc`; `/etc/zprofile` reorders PATH
  after `.zshenv`). Same for `~/.bashrc` / `~/.bash_profile` if you use bash.
- `launchctl setenv PATH "$HOME/.safe-chain/shims:…"` from a login LaunchAgent, so GUI apps,
  editors and agents launched from the Dock inherit it.
- Pin the age gate in the environment: `export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=48` in
  `~/.zshenv`. A repo can ship a `.aikido` file that lowers the gate; the environment variable wins.
- Prove it: `npm install --no-save safe-chain-test` must be refused, `npm safe-chain-verify` must
  say OK, and `/usr/bin/which npm` must print the shim from `zsh -lc`, `zsh -c`, `bash -lc`, `bash -c`
  and from `env -i HOME=$HOME /bin/zsh -lc '…'`.

To install something genuinely fresh, lower the gate for that one command in your own terminal:
`SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=0 npm i <pkg>`. Never set it permanently, never from an agent.

**SHOULD:** `pnpm` and `bun` block install scripts by default; keep that. Don't set
`ignore-scripts=true` globally for npm unless you know your native deps (esbuild, sharp, prisma,
electron) and are ready to `npm rebuild` them. **SHOULD:** use `corepack` for pnpm/yarn so each
repo's pinned version is used. **NICE:** Safe Chain does not cover `cargo`, `go install`, `gem`,
`brew`, `deno` — use `cargo install --locked`, pin Homebrew formulae, and treat those as unscanned.

---

## 3. Repositories you clone (MUST read, SHOULD automate)

A poisoned repo does not need `npm install` to hurt you:

- `.vscode/tasks.json` with `"runOn": "folderOpen"` runs when you open the folder. **MUST:** set
  `"task.allowAutomaticTasks": "off"` in VS Code and Cursor.
- A payload appended after a long run of blank space at the end of a config file (`postcss.config.mjs`,
  `tailwind.config.js` and similar) is out of sight when you open the file, and runs when the tool loads it.
- `.husky/`, `lefthook.yml`, `.git/hooks` run on your next commit.
- `.claude/settings.json`, `.codex/hooks.json`, `.cursor/hooks.json` can add hooks that run on every
  agent session. The ChainDrop npm worm (August 2026) wrote a session-start hook into `.claude/settings.json`
  ([Pillar Security](https://www.pillar.security/blog/chaindrop-when-opening-a-repository-becomes-execution),
  [Zscaler](https://zscaler.com/blogs/security-research/tracking-shai-hulud-inside-chaindrop-npm-worm)).
- `.npmrc` / `uv.toml` / `pyproject.toml` can point the package manager at an attacker's registry.
- A "font" file that is actually JavaScript, run as `node public/fonts/fa-solid.woff2`.

**SHOULD:** a global git hook (`git config --global hook.<name>.event post-checkout` +
`post-merge` + `post-rewrite`, git ≥ 2.54) that scans the files a clone/pull/checkout just brought
in for exactly those patterns and shows a notification before you run anything. The public IOC pack
for PolinRider lives at [OpenSourceMalware/PolinRider](https://github.com/OpenSourceMalware/PolinRider).
**MUST:** never run an interview take-home, a "demo project" from a recruiter, or a random GitHub
project on your main user account. Use a VM or container (§8).

**SHOULD:** `git config --global push.default simple`, no `--force` aliases, branch protection
with "no force push" on every repo you own. PolinRider spreads by rewriting a repo's newest commit, keeping its
author, date and message, and force-pushing it to every repo the infected developer can push to; disallowing
force-push defeats the technique, not just the signature.

---

## 4. AI coding agents (Claude Code, Codex, OpenCode, Cursor, Zed…)

Agents are not malicious, but they are suggestible and they run with your credentials. A line of
text in a README is enough to make one run `curl … | sh`. Treat the agent as an untrusted operator:

- **MUST:** the shims-first PATH from §2 must apply to the agent's shell. Check from inside each
  agent: `/usr/bin/which npm` → shim; `npm install --no-save safe-chain-test` → refused.
- **MUST:** a pre-command hook that refuses the obvious bypasses: a package manager by full path
  (`/opt/homebrew/bin/npm`, `.venv/bin/pip`), `PATH=` or `env -i` rewrites, `SAFE_CHAIN_*=0`,
  `--safe-chain-*` flags, `safe-chain uninstall`, registry overrides, `curl | sh`, `node file.woff2`,
  and any write to the files that enforce all of this (rc files, the hook config, the hook itself).
  Claude Code: `hooks.PreToolUse` on `Bash` and `Write|Edit|MultiEdit` with `… || exit 2` so a broken
  hook fails closed. Codex: `~/.codex/hooks.json` plus `~/.codex/rules/*.rules` with
  `prefix_rule(decision="forbidden")` for each real package-manager path. OpenCode: a plugin on
  `tool.execute.before`. Zed: `agent.tool_permissions.tools.terminal.always_deny`.
  The hook is pattern matching, not a sandbox; it stops an agent that slips or is talked into it.
- **MUST:** deny the agent edits to its own controls (`permissions.deny` → `Edit(~/.claude/settings.json)`,
  `Edit(~/.zprofile)`, …) and never accept a security baseline from an agent.
- **MUST:** put the same controls in a root-owned tier the agent cannot reach, because everything
  above lives in files your own user can write. Copy the hook script to
  `/usr/local/lib/safe-chain-agent/` (root:wheel 755), then
  `/Library/Application Support/ClaudeCode/managed-settings.json` (root:wheel 644) with the hooks
  pointing at that copy, the deny list and `"permissions": {"disableBypassPermissionsMode": "disable"}`;
  managed settings win over user and project settings. For Codex, `/etc/codex/requirements.toml`
  with `allowed_sandbox_modes = ["read-only", "workspace-write"]` and the off-switches as
  `[rules] prefix_rules` (`safe-chain uninstall`, `env -i`, …). Deny rules apply even under
  `--dangerously-skip-permissions`. After every hook update, re-copy the root version: the weekly
  check should diff the two. This protects against the agent, not against someone with your
  admin password.
- Keep the agent autonomous. The point is a filter on *what* it installs and *which files* it may
  touch, not a sandbox-only or approve-every-command mode; those get switched off within a week.
  Don't set `allowManagedHooksOnly` unless every hook you rely on is in the managed file too.
  The Codex requirements above are not that mode: `workspace-write` lets Codex work on its own inside the
  project, and only `danger-full-access`, which switches its sandbox off entirely, is ruled out. That root-owned
  file is the one control a Codex session can't rewrite for itself.
- **SHOULD:** pin MCP servers (`npx -y pkg@1.2.3`, not `@latest`); they start on every session.
- **SHOULD:** review project-level agent settings and hooks before opening a cloned repo in an agent.
- **NICE:** Claude Code `sandbox` (macOS Seatbelt) and Codex permission profiles for kernel-enforced
  filesystem and network limits — only if you accept the breakage (`docker`, `gh`, `terraform`,
  `osascript` need exclusions) and the slower loop.

---

## 5. Runtime: see and stop what runs

| Tool | Cost | Tier | What it adds |
|---|---|---|---|
| [BlockBlock](https://objective-see.org/products/blockblock.html) | free (donate) | **MUST** | Alerts the moment anything installs persistence (LaunchAgents, login items, cron). Enable Notarization, Block Scripts and ClickFix paste protection with heuristics. |
| [KnockKnock](https://objective-see.org/products/knockknock.html) | free | **MUST** | On-demand audit of ~20 autostart locations. Run weekly, diff against last week. Grant it Full Disk Access, and from launchd launch it as `open -n -W -a KnockKnock --stdout out.json --args -whosthere -skipVT` so TCC attributes the scan to the app, not to your script's shell. First-run dialog: leave "Include macOS components" and "Start at Login" off, keep update checks on. |
| [Little Snitch](https://obdev.at/products/littlesnitch/) | $ ~€59 | **SHOULD** | Outbound firewall. Enable the URLhaus / HaGeZi / NoCoin blocklists; add deny rules for known C2 domains and the blockchain "dead-drop" APIs malware uses to fetch its next stage. Honest caveat: if your terminal and editor have allow-any rules, it will not stop a script from phoning home. |
| [LuLu](https://objective-see.org/products/lulu.html) | free | alternative | If you don't buy Little Snitch. |
| [Micro Snitch](https://obdev.at/products/microsnitch/) / [OverSight](https://objective-see.org/products/oversight.html) | $5 / free | NICE | Mic and camera use. |
| EDR (CrowdStrike Falcon, Bitdefender, …) | company-provided | SHOULD | Behavioural detection. Exclude repo/cache paths from *signature* scanning (it only deletes build artifacts) but never from the behavioural engine; ask your admin what the server-side exclusions are. |
| [tirith](https://github.com/sheeki03/tirith) | free | NICE | Terminal guard against pasted homographs, `curl \| bash`, ANSI-escape injection. |

---

## 6. Secrets: assume the payload runs, make it find nothing

- **MUST:** keep SSH keys in a protected SSH agent: [1Password](https://1password.com/)'s ($), free
  [Secretive](https://github.com/maxgoedjen/secretive) (keys made in the Secure Enclave) or the free
  [Bitwarden](https://bitwarden.com/help/ssh-agent/) agent. Import or create your keys there, delete the files from
  `~/.ssh`, and every use needs your approval. A stealer reading `~/.ssh` gets nothing. Another agent counts too,
  recorded as an accepted decision. Minimum fallback: `ssh-keygen -p -f ~/.ssh/<key>` on every key.
- **MUST:** no plaintext keys lying around. Audit with
  `fd -H -t f '(\.pem|\.key|credentials|sa-key.*\.json|\.env)$' ~ -E Library -E node_modules`.
  Anything in `~/Downloads` or `~` itself is a leak waiting to happen.
- **MUST:** GitHub tokens are the blast radius. `gh auth login` gives a classic OAuth token with full
  `repo` scope (and often `workflow` / `admin:org`); any process running as you can read it with
  `gh auth token`. Use fine-grained PATs, scoped to the org, with an expiry; let your org restrict
  classic tokens. Same for cloud CLIs: short-lived SSO sessions, not long-lived keys.
- **SHOULD:** [gitleaks](https://github.com/gitleaks/gitleaks) as a pre-commit hook and
  `gitleaks git <repo>` on anything you inherit; [git-filter-repo](https://github.com/newren/git-filter-repo)
  to purge what you find; GitHub secret-scanning push protection on your orgs ($, Team plan add-on).
- **SHOULD:** rotate on a schedule, not on an incident. Keys and tokens older than a year are
  probably in a backup, a transcript or a log somewhere.
- **NICE:** AI-agent transcripts (`~/.claude/projects`, `~/.codex/sessions`, OpenCode's DB) contain
  every secret you ever pasted. Scrub them weekly or exclude them from backups.
- **$ NICE:** two [YubiKeys](https://www.yubico.com/) (~$50 each) as GitHub / Google / 1Password
  second factors; passkeys where offered.

---

## 7. Scanners worth having (all free, SHOULD)

| Tool | Use |
|---|---|
| [osv-scanner](https://github.com/google/osv-scanner) | `osv-scanner scan source -L <lockfile>`: known CVEs in a project's pinned deps |
| [pip-audit](https://github.com/pypa/pip-audit) | same for Python environments |
| [gitleaks](https://github.com/gitleaks/gitleaks) | secrets in git history |
| [cosign](https://github.com/sigstore/cosign) | verify signed container images and release artifacts |
| [shellcheck](https://www.shellcheck.net/) · [actionlint](https://github.com/rhysd/actionlint) | unsafe shell, broken GitHub Actions |
| [nuclei](https://github.com/projectdiscovery/nuclei) | NICE: scan your own exposed services |
| `brew vulns --fix-available` | CVEs in installed Homebrew formulae |

Dependabot / Renovate on every repo you own: free, and the only thing that catches the npm-package
arm *after* the fact.

---

## 8. Isolation for anything untrusted (SHOULD)

- [OrbStack](https://orbstack.dev/) (free for personal use, $ for work) or [UTM](https://mac.getutm.app/):
  a throwaway Linux VM or container with only the repo folder mounted, no home directory, no keys,
  no cloud logins. Interview take-homes, random GitHub projects, "please review my code" zips.
- Dev containers for repos you work on regularly but did not author.
- A separate macOS user account for the truly sketchy, if you must run it natively.

---

## 9. Browser (MUST)

- A password manager's extension (1Password, Bitwarden, or iCloud Passwords for Apple Passwords users), built-in
  password manager off and its saved passwords deleted. uBlock Origin or Brave shields.
- Remove extensions you don't use. Crypto wallet extensions on a dev machine are the first thing a
  stealer goes for: hardware wallet or a separate device.
- A separate browser profile for development, with no personal logins.
- DNS filtering with malware blocklists on: Cloudflare `1.1.1.2` or Quad9 `9.9.9.9` (both free), or
  [NextDNS](https://nextdns.io/) ($ beyond its free tier). The free resolvers meet this MUST.

---

## 10. Automate it, or it decays (SHOULD)

Two launchd jobs with a Notification Center banner on failure, and a daily health check that alerts
when a job is unloaded, failing or overdue:

- **Weekly update (Mon):** `brew update && brew upgrade && brew vulns`, Safe Chain self-update
  (pinned, checksum-verified), `uv tool upgrade --all`, global npm, nuclei templates, transcript scrub,
  90-day log retention.
- **Weekly security check (Wed):** posture (§1) · Safe Chain still first on PATH in every shell type,
  test package still refused · agent hooks still registered, control files unchanged (sha256 vs
  baseline) · persistence diff (LaunchAgents/Daemons, login items, cron, agent hooks, KnockKnock) ·
  non-loopback listeners diff · IOC sweep of the machine and repos · git-scan findings · SSH keys
  without passphrase. New entries alert until **you** accept them into the baseline.

Keep the scripts under `~/.local/bin`, logs under `~/.local/var/log`, and make the security check
refuse to accept a baseline from an agent.

---

## 11. GitHub / org side (for whoever owns the orgs)

- No force-push and no direct push to protected branches, everywhere.
- Classic PATs restricted; fine-grained PATs with approval and expiry.
- Secret scanning with push protection. Dependabot alerts on.
- Pin GitHub Actions by commit SHA, not by tag (tags get re-pointed at malware).
- Treat a red CI on a workflow-only or config-only commit as suspicious, not flaky.
- Signed commits (SSH signing through the 1Password agent is the easiest).

---

## 12. If a scan ever turns red

The step-by-step version for anyone is [`docs/if-red.md`](../docs/if-red.md); `/if-red` walks through it.

1. Take the Mac off the network (Wi-Fi off, cable out), leave it switched on, and stop using it. Don't run the
   suspicious code, open it in an editor with automatic tasks, or "just look" in a Node REPL.
2. Rotate from a clean device, never from the suspect Mac, in this order: GitHub / cloud tokens, SSH keys,
   browser-saved sessions (sign out everywhere), wallet seeds if any wallet extension is installed, then
   everything in `.env` files.
3. Get help: your employer's IT or security team on a work Mac, an incident-response service on your own.
4. Don't wipe before deciding with them: the disk is the evidence of what was taken. Keep the sample (zip it,
   don't delete it) and report: [OpenSourceMalware](https://github.com/OpenSourceMalware), npm / PyPI security,
   your EDR vendor.

---

## What costs money

Every MUST can be met for free. Where a paid tool is named above, this is the free way to meet the same control;
prices change, so check each vendor's page.

| Paid | What it's for | Free way to meet it |
|---|---|---|
| 1Password | SSH agent (BL-SE-01, MUST), browser extension (BL-BR-02, MUST) | Secretive or Bitwarden's SSH agent; Bitwarden's or iCloud Passwords' extension |
| NextDNS (beyond its free tier) | DNS filtering (BL-BR-06, MUST) | Cloudflare `1.1.1.2` or Quad9 `9.9.9.9` |
| Little Snitch | outbound firewall (BL-RT-03, SHOULD) | LuLu |
| Micro Snitch | microphone and camera monitor (BL-RT-04, NICE) | OverSight |
| OrbStack for work use | VM or container tool (BL-IS-01, SHOULD) | UTM, Colima, Lima or Podman |
| YubiKeys | second factor (§6, not checked) | passkeys where offered |
| GitHub Secret Protection | push protection for an org (§6, §11, not checked) | gitleaks as a pre-commit hook (BL-SE-06) |
| A hardware wallet | only if you hold crypto (§9) | keep wallets off the dev machine (BL-BR-04) |

The Objective-See tools (BlockBlock, KnockKnock, LuLu, OverSight) are free; they take donations. Endpoint
protection is usually provided by your employer.

---

## 30-minute checklist

- [ ] FileVault, firewall + stealth, auto-updates, sharing services off
- [ ] Safe Chain installed with `--ci`, shims first in `.zshrc`, `.zprofile`, launchd env; `safe-chain-test` refused from `zsh -lc`
- [ ] `SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=48` in `~/.zshenv`
- [ ] VS Code / Cursor `task.allowAutomaticTasks: off`
- [ ] BlockBlock installed, Full Disk Access granted, protections on; KnockKnock installed with Full Disk Access, run once
- [ ] A protected SSH agent on (1Password, Secretive or Bitwarden), no key files without passphrase, no `.pem` in `~/Downloads`
- [ ] `gh auth token` is a fine-grained PAT with expiry, not a classic `repo` token
- [ ] Browser password manager off, wallet extensions off the dev machine
- [ ] Agent hooks: shims-first PATH, pre-command guard, config edits denied, MCP servers pinned
- [ ] Root-owned copy: `managed-settings.json` + `/etc/codex/requirements.toml` + guard under `/usr/local/lib`
- [ ] Weekly update + weekly security check in launchd, with notifications
- [ ] A VM for untrusted code, and the habit of using it

---

## Credits

fortkeep's malware indicators (the repo scanner, `fixes/files/git-scan-new-files`, and the live-malware check,
`checks/macos/GD-RT-03.sh`) are built from public research. Each file's header maps every indicator family to its
source; each lesson's "Real attack" line links its own. The main sources:

- [OpenSourceMalware](https://opensourcemalware.com): the PolinRider dossier
  ([github.com/OpenSourceMalware/PolinRider](https://github.com/OpenSourceMalware/PolinRider)) and its research
  blog, the backbone of the PolinRider and NullReceiver indicators.
- The reporters in GitHub Community discussions
  [188732](https://github.com/orgs/community/discussions/188732),
  [197873](https://github.com/orgs/community/discussions/197873) and
  [198490](https://github.com/orgs/community/discussions/198490).
- Sonatype Security Research, OX Security, Bitdefender Labs, Palo Alto Networks Unit 42, Pillar Security,
  Zscaler ThreatLabz, StepSecurity, Abstract Security, eSentire and Microsoft Threat Intelligence, for their
  write-ups of these campaigns.
- Cursor's [security notice](https://cursor.com/blog/claude-code-extension-security-notice) on the trojanized
  Claude Code extension.
- The OpenSSF malicious-packages data, through [OSV](https://osv.dev).
- [MITRE ATT&CK](https://attack.mitre.org), for the generic techniques.
- The [macOS Security Compliance Project](https://github.com/usnistgov/macos_security) (mSCP,
  [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)): the macOS controls name its matching rule IDs (`mscp` in
  `controls/baseline.yaml`).
- The community scanners [Improwised/polinrider-scanner](https://github.com/Improwised/polinrider-scanner) and
  [heisdeku/clean-injected-loader](https://github.com/heisdeku/clean-injected-loader), used as pointers to their
  own sources.

Only facts are taken from these: indicator values, names and behaviour, written in fortkeep's own words and code.
Nothing is copied from GPL-licensed tools, from CIS Benchmark text, or from repositories without a licence
(the OpenSourceMalware repository has none): no code, rule files or prose.
