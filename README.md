<h1 align="center">fortkeep</h1>

<p align="center"><strong><em>A security checkup for your Mac that your coding agent runs with you.</em></strong></p>

<p align="center">
  <a href="https://github.com/b0dea/fortkeep/actions/workflows/ci.yml?query=branch%3Amain"><img alt="CI status" src="https://github.com/b0dea/fortkeep/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="https://github.com/b0dea/fortkeep/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/b0dea/fortkeep?color=blue"></a>
  <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-green.svg"></a>
  <img alt="macOS 15 or later" src="https://img.shields.io/badge/macOS-15%2B-lightgrey.svg">
</p>

<p align="center">
  <a href="#try-it">Try it</a> ·
  <a href="#install">Install</a> ·
  <a href="#safety">Safety</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#faq">FAQ</a>
</p>

fortkeep checks a developer's Mac against a practical security baseline, with [Claude Code](https://code.claude.com/docs),
[Codex](https://developers.openai.com/codex) or [OpenCode](https://opencode.ai) as your guide:

- **It explains in plain words.** Your agent runs the read-only checks, then goes through the results with you, most
  important first, and says why each gap matters. Teach mode adds a short lesson per control.
- **It changes nothing without your answer.** Each fix is one change you approve, with a backup, an undo and a line
  in a change log. Admin steps are commands you type yourself.
- **It is written for people who aren't security experts.**

It aims at how developer Macs get compromised today: a malicious or hijacked npm or PyPI package, a poisoned repo
(a fake take-home test, a "please review my code" project), an AI agent tricked into running a bad command, and
secrets lying around in files. It is not an antivirus, not device management and not a sandbox.

## Try it

Once it's [installed](#install), `fortkeep check` runs every check from your Terminal, no agent needed:

```console
$ fortkeep check
fortkeep check: 2026-11-19 17:54 UTC, macOS 27.2.1

MUST
  FAIL      BL-OS-02  Firewall on with stealth mode
            Firewall is on; stealth mode is off
  FAIL      BL-SC-01  Safe Chain installed, with shims for scripts and agents
            safe-chain is not on your PATH
  ERROR     BL-BR-04  No crypto wallet extensions on this Mac
            Something outside fortkeep stopped this check (signal KILL). It is often a security tool mistaking a read-only check for malware; ask whoever manages it for an exclusion, and never turn it off.
  ACCEPTED  BL-SE-01  SSH keys live in a protected SSH agent (1Password, Secretive or Bitwarden)
            your reason: My keys live on a hardware key
  PASS      BL-OS-01  FileVault on
  PASS      BL-OS-03  Gatekeeper on
  PASS      BL-OS-07  Screen locks immediately

SHOULD
  FAIL      BL-RC-02  Global git hook scans what a clone, pull or checkout brings in
            No global git hook scans what a clone or pull brings in
  FAIL      GD-AI-01  Agent control files unchanged since your baseline
            No accepted baseline yet: type fortkeep baseline accept in the Terminal app
  PASS      BL-AU-02  A weekly security check runs and is up to date

NICE
  NA        BL-SE-08  AI-agent transcripts kept out of backups
            No agent transcripts on this Mac
  PASS      BL-RT-06  tirith terminal guard installed

ACCEPTED 1 · ERROR 1 · FAIL 4 · NA 1 · PASS 5
Next: fortkeep agent, then type /fix (in Codex, $fix). Why one matters: fortkeep explain ID.
```

That is sample output from the test fixtures: real control titles and layout, stand-in checks and a short list. A
real run checks every control and takes minutes. Then ask why one matters:

```console
$ fortkeep explain BL-OS-02
# BL-OS-02 · Firewall on with stealth mode

**Why:** The firewall stops other devices on the same network from connecting to services on your Mac. Stealth mode
makes the Mac ignore probes, so it is harder to find at all.
...
```

To fix things, start your agent with `fortkeep agent` and type `/posture`.

## Install

You need macOS 15 or later, Apple's Command Line Tools (`xcode-select --install`), and Claude Code, Codex or OpenCode
for the fixes.

**With Homebrew:**

```sh
brew install b0dea/tap/fortkeep
fortkeep
```

**Or with the installer.** Download it, compare its SHA-256 with the one below, and only then run it. Never pipe it
into a shell.

```sh
curl -fsSLO https://raw.githubusercontent.com/b0dea/fortkeep/main/install.sh
shasum -a 256 install.sh
bash install.sh
```

The SHA-256 of `install.sh` for the current release: `PINNED-AT-RELEASE`

Both put fortkeep in `~/.local/share/fortkeep`: a git checkout of one signed release. The installer refuses any
release but the one it pins, by tag and commit, checked before anything from it runs, and refuses a tag that isn't
signed by a maintainer that release lists. Those pins are what you trust on first install, so check they match the
ones in the [release notes](https://github.com/b0dea/fortkeep/releases). From then on `fortkeep update` moves it only
to releases a maintainer it already trusts signed.

## The agent workflow

```sh
fortkeep agent          # starts your coding agent in the fortkeep folder, so its guards and skills load
```

Then type:

| Command | What it does |
|---|---|
| `/posture` | First time: asks about teach mode, the set-ups that apply and any private folders. Then runs the check and explains the results. |
| `/fix` | Works through the failures one at a time, each only after your answer. Also undoes a fix. |
| `/summary` | A posture summary you can share: each control's title, level and result, and your reason for any you kept. No file paths or evidence. |
| `/scan` | Before you open or install a repo: scans it, or the repos in one folder, for signs it is poisoned. Reads only. |
| `/if-red` | What to do when a check finds something that looks like real malware. |

Each agent loads the same instructions, skills and guard scripts; only the wiring differs
([docs/agents.md](docs/agents.md)):

| | Claude Code | Codex | OpenCode |
|---|---|---|---|
| Start | `fortkeep agent claude` | `fortkeep agent codex` | `fortkeep agent opencode` |
| First run | accept "trust this folder" | trust the folder, then "Trust all and continue" for its hooks | nothing: the guard plugin loads by itself |
| Start a skill | `/posture` | `$posture` | `/posture` |
| How you approve a fix | pick `Apply <ID>` in its question | type `Apply <ID>` as your whole message | pick `Apply <ID>` in its question |

If the agent's first message warns that this copy isn't exactly a signed release, don't run fixes: reinstall,
unless you changed it yourself.

## Safety

- **The checks only read.** They report how the Mac is set up and change nothing.
- **The agent's session is allow-listed.** In the fortkeep folder the agent may run only fortkeep's own scripts, read
  only fortkeep's own files and write none of them. Guard scripts check every tool call
  ([docs/agents.md](docs/agents.md)).
- **Every change needs your answer.** A fix runs only after you answer `Apply <ID>` for that one change. It keeps a
  backup, has an undo, and is logged in `reports/change-log.md`.
- **It never runs `sudo`.** Admin steps are commands you type yourself in the Terminal app, each ending with
  `sudo -k`.
- **Private folders stay private.** Name a folder and every check skips it, and the agent never lists, opens or
  searches it. Only you can take one off the list.
- **Secrets are shown as counts.** Results show counts, lengths or fingerprints of secrets, never their values.
- **Releases are signed.** Your copy runs version tags a maintainer signed with an SSH key listed in
  [`.github/allowed_signers`](.github/allowed_signers), and warns when it has local changes.
- **It is not a sandbox.** The guards stop agent mistakes and prompt injection that asks for a guarded action. They
  don't stop a malicious agent program or anything already running as you.
  [docs/threat-model.md](docs/threat-model.md) says exactly what they do and don't cover.

## Privacy

Results stay on your Mac. There is no telemetry, and nothing is uploaded. The few times fortkeep uses the network:

- installing and `fortkeep update` fetch the release tags from GitHub;
- the DNS-filtering check looks up one known-bad test name, to see whether it is blocked;
- the Safe Chain checks run Safe Chain's own self-test, and ask npm, through Safe Chain, for its harmless test
  package;
- the weekly check, if you turn it on, runs `brew update` and `brew vulns`.

[docs/what-fortkeep-touches.md](docs/what-fortkeep-touches.md) lists every path fortkeep reads and writes, every network
use, and the macOS privacy prompts a first run may show.

## What it checks

Three layers: a **baseline** whose controls are each MUST, SHOULD or NICE, a stricter **gold** layer, and opt-in
**overlays** for set-ups such as a managed antivirus, a TLS-inspecting proxy or secrets kept out of the agent's
context. [controls/baseline-source.md](controls/baseline-source.md) is the full baseline with its reasoning, and
[controls/](controls/) holds every control.

| Area | For example |
|---|---|
| macOS | FileVault, firewall with stealth mode, Gatekeeper, automatic updates, sharing off, immediate screen lock, Touch ID for `sudo` |
| Malicious packages | [Safe Chain](https://github.com/AikidoSec/safe-chain) first on PATH in every shell, apps and the agent's own shell; a minimum package age; pnpm and bun blocking install scripts |
| Repos and git | editor automatic tasks off; a git hook that scans what a clone or pull brings in; a sweep of the repos and editor extensions already on the Mac |
| AI coding agents | a guard before every agent command; the agent unable to edit its own controls; a root-owned copy of them; MCP servers pinned |
| Secrets | SSH keys with a passphrase in a protected agent; no plaintext keys lying around; fine-grained tokens; short-lived cloud sessions; gitleaks before every commit |
| Runtime | BlockBlock, KnockKnock, an outbound firewall, endpoint protection; new autostart items or listeners since your baseline |
| Browsers | built-in password manager off; a password manager extension and an ad blocker in every profile; no crypto wallets; DNS filtering |
| Upkeep | security scanners, a VM or container tool for untrusted code, a weekly update job and security check |

Every MUST can be met for free, and a control that names a tool also accepts its named alternatives: Secretive or
Bitwarden for 1Password's SSH agent, for example ([what costs money](controls/baseline-source.md#what-costs-money)).

## Urgent findings

A few checks look for signs of live malware. If one fails, fortkeep says so first and `/if-red` walks you through what
to do: go offline, stop using the Mac, change passwords and keys from a clean device, and get help.
[docs/if-red.md](docs/if-red.md) has the steps, written to work without fortkeep or an agent.

## Commands

Run `fortkeep` alone for the commands, the last check and what to do next.

**`fortkeep check [--only ID]... [--json]`** runs the checks, read-only, and prints the results grouped as above.
`--only` rechecks those controls after a full run. `--json` prints the full results instead. Exit status: 0 nothing
failed, 1 something failed or couldn't be checked, 2 the check didn't finish.

**`fortkeep explain ID`** prints the lesson for one control: why it matters, a real attack, how to check it yourself,
and how to fix it.

**`fortkeep scan FOLDER`** scans one repo, or the git repos in a folder, for signs it is poisoned, before you open,
install, build or run it. It reads the repo's files (tracked or not, except node_modules), git hooks and history, runs
nothing from them, and skips private folders. Exit status: 0 nothing flagged, 1 signs of a poisoned repo, 2 refused, 3 only lower-confidence findings, 4
not everything was scanned.

**`fortkeep agent [claude|codex|opencode]`** starts your coding agent in the fortkeep folder, so its guards and skills
load. With no name, the first one installed.

**`fortkeep summary [--name NAME]`** writes the posture summary, as `/summary` does, and asks the name to show on it.
It is self-reported: anyone with your account could edit it before sharing.

**`fortkeep update`** moves your copy to the newest signed release. Use it instead of `git pull`.

**`fortkeep version [--json]`** says which release this is, its commit, whether anything changed locally, and where
it is installed.

**`fortkeep accept ID "reason"`** keeps a failed control as it is, with your reason; **`fortkeep accept --remove ID`**
takes that back. **`fortkeep private add|remove|count`** manages the folders every check skips.
**`fortkeep baseline accept`** accepts what is on the Mac now as your baseline. These are yours to type: the agent
can't remove a private folder or accept a baseline.

**`fortkeep uninstall`** removes fortkeep's own state. It refuses while a fix that installed something is still
applied, prints the admin changes you may want to revert yourself, asks before removing anything, and leaves the
fortkeep folder for you to delete.

## How it differs

- **[Objective-See](https://objective-see.org/tools.html)** (BlockBlock, KnockKnock, LuLu, OverSight): free tools
  that watch for persistence and network use. fortkeep complements them, and checks they're installed and running.
- **[Lynis](https://cisofy.com/lynis/)**: a broad hardening audit for Unix-like systems, aimed at administrators.
  fortkeep is narrower, about developer threats, and explains and fixes with you.
- **[osquery](https://osquery.io/) and [Fleet](https://fleetdm.com/)**: query device state across a fleet from a
  server. fortkeep is one Mac and no server.
- **[mSCP](https://github.com/usnistgov/macos_security)**: the macOS Security Compliance Project's baselines and
  scripts for compliance frameworks. fortkeep isn't a compliance tool, but its macOS controls name the matching mSCP
  rules (`mscp` in `controls/baseline.yaml`; mSCP is CC BY 4.0).
- **[Santa](https://github.com/northpolesec/santa)**: allows or blocks which programs may run. fortkeep blocks
  nothing; it checks settings.
- **[Pareto Security](https://paretosecurity.com/)**: a menu-bar app that checks common macOS settings. fortkeep also
  covers packages, repos and coding agents, and works through your agent.
- **[StepSecurity Dev Machine Guard](https://www.stepsecurity.io/dev-machine-guard)**: inventories agents, MCP
  servers, extensions and packages across developer machines, against StepSecurity's threat intelligence. fortkeep
  runs on one Mac and reports nowhere.

## FAQ

**A check says "Something outside fortkeep stopped this check".** A security tool on the Mac, usually antivirus or
endpoint protection (EDR), ended a read-only check it mistook for malware. The Mac isn't unsafe because of it; that
check just has no answer. Ask whoever manages the tool for an exclusion for the fortkeep folder. Never turn the tool
off to make a check pass.

**Microsoft Defender quarantined a fortkeep file.** fortkeep's scanners look for malware by its markers, and an
antivirus can mistake that for malware. The repo keeps every marker in pieces for this reason, so tell us in an issue
which file it was. Then restore the file from Defender's quarantine, or ask your IT team to. If you're unsure, delete
the folder and reinstall.

**Why Safe Chain, and 1Password?** [Safe Chain](https://github.com/AikidoSec/safe-chain) is free and open source: it
blocks packages on a malware feed and refuses versions published in the last 48 hours, when most hijacked versions are
caught. 1Password is one way to keep SSH keys in a protected agent; Secretive and Bitwarden are free alternatives,
and fortkeep accepts them. The baseline's
[what costs money](controls/baseline-source.md#what-costs-money) section lists a free way to meet every MUST.

**Does it send anything?** No telemetry and no results. The network uses are listed under [Privacy](#privacy).

**Can I use it for my team?** Overlays cover set-ups such as a managed antivirus or a TLS-inspecting proxy. For your
own controls or a stricter policy, fork it: set your fork's name in `checks/lib/repo.sh` (`FORTKEEP_RELEASE_NAME`) and
the clone URL in `install.sh`, and put your own maintainers' keys in `.github/allowed_signers`. Copies of your fork
then update only to releases you sign.

**How do I verify a release?** [SECURITY.md](SECURITY.md#verifying-a-release) shows how to check a tag's signature
and compare the signing keys with the ones the maintainers publish on GitHub.

**Can I clone it myself?** Yes: `git clone https://github.com/b0dea/fortkeep ~/.local/share/fortkeep`, then
`~/.local/share/fortkeep/bin/fortkeep update`. A clone trusts the signers on `main` as they are that day; the installer
pins a release instead.

## Contributing

Contributions are welcome: a check that gives the wrong result, a control, a lesson, a fix. People start with
[CONTRIBUTING.md](CONTRIBUTING.md), agents with [AGENTS.md](AGENTS.md). What's planned is in
[docs/ROADMAP.md](docs/ROADMAP.md), what changed in [CHANGELOG.md](CHANGELOG.md). Follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Report a vulnerability privately, as [SECURITY.md](SECURITY.md) says; never in a public issue.

## Licence and credits

[MIT](LICENSE). fortkeep's malware indicators are built from public research; the
[credits](controls/baseline-source.md#credits) name the sources.

fortkeep is not affiliated with Apple, Anthropic, OpenAI, Aikido Security, 1Password, Objective-See, or any other
vendor or project named here.
