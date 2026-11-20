# Threat model

fortkeep guards one thing: a coding agent, in a session a person started to check their Mac, doing something the
person didn't approve. It stops agent mistakes, and prompt injection that asks the agent for a guarded action: text in
a repo, a web page or scan output telling it to run, read or change something.

It does not stop:

- a malicious or modified agent program. The guards are hooks the agent program runs; a program that skips them
  skips them.
- anything already running as the person's macOS user. That can change any file the user can, fortkeep's included:
  its guards, approvals, results and the start-up files its fixes edit.

fortkeep is not an antivirus and not a sandbox. Its checks report how the Mac is set up; they don't block anything.

## A person's session

A person's session is any session that isn't a [development session](#development-sessions). In it the agent is a
guide: it runs fortkeep's own scripts and reads fortkeep's own files, and needs almost nothing else. So what it may do is
a short allow-list (`.claude/hooks/allow-list`), not a list of bad commands.

**Shell.** A command must be exactly one of fortkeep's entry points, run from the repo folder, spelled as the skills
write them, with arguments fortkeep validates:

- the check runner and its helpers in `checks/`: `run.sh`, `diff.sh`, `configure.sh`, `detect.sh`, `overlays.sh`,
  and `show.sh`, which prints a file under the read rules below (Codex has no read tool);
- `checks/ask.sh`, which prints the one question the person answers to approve something;
- `checks/accept.sh` and `checks/private.sh add` and `count`, which act only on the person's recorded answer (for a
  private folder, its answer to the question naming that folder);
- `checks/scan.sh`, which scans one folder the person names for signs of a poisoned repo: read-only, it runs nothing
  from the folder, and refuses a private folder, `/`, the home folder and the folders above it;
- `summary/name.sh` and `summary/build.sh`;
- `fixes/macos/<ID>.sh apply` and `undo`, which the agent asks before running. A fix is refused while the agent is in
  bypass, auto or accept-edits mode, where it would run without the person's prompt.

Everything else is refused: any other program, pipes, redirections, variables, command substitutions, globs, several
commands on one line, and characters beyond ASCII (except letters inside quotes in a name or a reason).

**Read tools** work only inside the fortkeep folder and the agent's own folders for this project (its scratch folder
and Claude Code's project folder, with memory and saved tool output). They never read `private-paths`,
`reports/.approvals`, `.git`, a file named as a secret (`.env`, `.env.*`, `*.pem`, `*.key`, `id_*`, but not `*.example`)
or a file's named fork (`FILE/..namedfork/...`), and a search may not start at a folder that holds any of them. A
search pattern with braces (`{a,b}`) is refused, since an alternative could name a folder outside the one checked.
Private folders are outside the fortkeep folder, so read tools can't reach them at all: there is no name comparison
left to fool. The Artifact tool only publishes the summary page, `reports/latest/posture-summary.html`, as a new page
that stays private until the person shares it; any other file, action or destination is refused.
A guard that stops with any status but 0 or 2 (a crash, or a library that stops it) blocks the call: the agents go
ahead on any other status.

**Write tools** work only in this project's scratch folder and the plan folder. The plan folder holds every
project's plans, so it can't be read. Memory is never written: what lands there becomes standing instructions for
every later session. Nothing in the fortkeep folder is written either: `checks/configure.sh` saves the person's
settings and `checks/run.sh` writes results.

**Any other tool** is refused, in all three agents, except the ones that touch no file and run no command: the
question tool, the todo tools, skills, plan mode and Claude Code's tool loader. Web fetch and search are refused, since
a URL or query could carry what the agent read off the Mac; Codex's hosted web search reaches no hook, so
`.codex/config.toml` turns it off. Subagents and MCP tools are refused: their calls are not known to pass through the
guards.

What this closes: rewriting the guards, checks or fixes; committing to hide a change; forging an approval by any
spelling of its path; running a file dropped in `reports/`; starting another agent non-interactively to record an
approval; writing results by hand; and planting instructions in the agent's memory.

## Development sessions

Development sessions are for people changing fortkeep. One needs both `FORTKEEP_DEV=1` in the agent's environment and
the file `~/.config/fortkeep/dev`, which the person creates once in the Terminal app. The variable alone isn't enough:
a planted agent config or launcher can set it for commands no guard sees. The marker is read from the account's own
home folder, not `$HOME`, and no tool or script in a person's session writes there.

A development session keeps the older deny-list guards, which refuse known-bad commands and allow the rest and have
the [known limits](#known-limits) below, and the release checks let an untagged copy through.

## The approval

A fix runs only after the person answers `Apply <ID>` or `Undo <ID>`. Accepting an unmet control takes
`Accept <ID>`, and adding a private folder, which hides it from every check, takes `Add private folder`.

- **What it is.** A hook records the person's own answer: an option they picked in the agent's question tool, in
  exactly the question `checks/ask.sh` prints for that action, or, in Codex, a message that is exactly that answer.
  It writes a one-use token under `reports/.approvals`, which the script that acts on it consumes. A token expires
  after five minutes. The model can't write the person's messages, `guard.sh` refuses a question that arrives with
  its answers already filled in (only the model could have written them), a subagent's prompt records nothing, and in a
  person's session the model can't reach `reports/.approvals` by any tool. The hook records nothing when another agent
  started this one (`codex exec`, `claude -p` or `opencode run` inside a session). `checks/accept.sh` and
  `checks/private.sh add` need no token when the person types them in a terminal app.
- **What it isn't.** It is not a cryptographic proof. The token is a file the person's own account can write, so
  anything running as that user can make one. It shows that the person answered in a session where the guards ran;
  it does not show that the agent described the change honestly. The fix script and its lesson say what it changes.
- **An accepted control.** The question names the reason, and the token holds it: `checks/accept.sh` records only
  that reason, so the agent can't put its own words in the person's mouth. In Codex the typed answer carries it
  (`Accept <ID> <reason>`).
- **A private folder.** The question names the folder, in the one spelling `checks/private.sh` stores (absolute, no
  `.` or `..`), and the token holds that folder: `checks/private.sh add` takes only it. In Codex the typed answer
  names it (`Add private folder <path>`). `/`, the home folder (from `HOME` and from the account), a folder above
  it, and the fortkeep folder or a folder above it are never asked about or added from an agent's session, as spelled,
  with symlinks resolved or by physical path (`/System/Volumes/Data/Users/…` included), in any letter case. Hiding one would blind every check; the person can still add it in
  a terminal app.

## Checks

- Results come only from `checks/run.sh`. The agent never decides PASS or FAIL.
- A check never prints a secret's value: counts, lengths or fingerprints at most.
- A check never uses the network, with one exception: when this Mac's DNS servers aren't on BL-BR-06's known list, it
  looks up one published malware test name (and `example.com` only if that gets no answer) to see whether DNS
  filtering blocks it.
- Checks don't trust the environment they are started from. System folders come first on `PATH`, so a fake
  `fdesetup` earlier on it can't turn the FileVault check to PASS; checks that look at the person's tools read the
  person's own `PATH` for that. Checks run under `bash -p` with `BASH_ENV` and `ENV` unset, with no exported shell
  function, and `checks/run.sh` drops the test-only overrides outside the tests.
- Private folders are skipped by every check.

## Integrity

People's Macs run signed releases: version tags signed by a maintainer whose SSH key is in
`.github/allowed_signers`. [SECURITY.md](../SECURITY.md#verifying-a-release) shows how to verify one by hand.

- **What is checked.** Session start, the fix library, the weekly job and the scripts the person runs verify that the
  copy is a signed release with no local changes (`checks/update.sh`, which moves the copy onto one, checks only the
  changes). That covers every tracked file (content, type and executable bit),
  the untracked and ignored files where agents load configuration (`.claude/`, `.codex/`, `.agents/`, `.opencode/`,
  `opencode.json`, `.mcp.json` and local instruction files), git hooks, `info/attributes`, and local git settings
  that run a command or change what git reads. A failed check warns at session start and refuses everywhere else.
- **Who may sign.** A release counts only when a key this Mac trusts signed it: the signers of the first release it
  ran, then those each newer release names (`~/.config/fortkeep/release-signers`). A commit can't add its own signer.
- **Downgrades.** The highest release this Mac ran is recorded in `~/.config/fortkeep/highest-release`, so moving to an
  older one warns.
- **Updates.** `checks/update.sh` fetches only over https or ssh, and only from the place recorded at the first
  verified install (`~/.config/fortkeep/origin`); it refuses a copy that names another place, or several, and a
  `url.<base>.insteadOf` or `pushInsteadOf` setting, in the copy's git config or the person's own, that rewrites
  that place. Its messages never print an address, which can carry a token. It moves only to a release a trusted key
  signed, and once on a release only forward.
- **Where the record lives.** The origin, the trusted signers and the highest release are kept in the account's own
  home folder, read from the directory service, so a changed `HOME` can't point fortkeep at another record.
- **First install.** `install.sh` and the Homebrew formula pin one release by tag and commit. They refuse a clone whose
  tag isn't exactly that commit, check that before running anything from it, and refuse a tag that release's own
  signers didn't sign. That signature check adds little on its own: the pins are the trust root. They live on `main`
  (in `install.sh`, with its SHA-256 in the README) and in the tap repo (the formula), so whoever can change those
  decides what a fresh install gets. Branch protection on both, and the pins printed in each GitHub release's notes,
  are what guard them; [SECURITY.md](../SECURITY.md#verifying-a-release) shows how to check a release's signature by
  hand before installing. A plain `git clone` trusts `main` as it is that day until its first `checks/update.sh`.
- **Releases.** `make release` refuses a copy with local changes or with the extra files and git settings above. Git
  hooks are allowed to be there, since `make install` puts lefthook's in place, but the tag is made and removed with
  no hook folder (`core.hooksPath=/dev/null`), so none runs, `reference-transaction` included. It keeps the tag only if copies on the last release and fresh clones
  would both accept it. It checks this directly, because a maintainer runs it in development mode.
- **Not covered.** Files fortkeep installs outside its folder, such as the git scan hook and the weekly job's
  launcher, are not part of the signature check.

## Admin steps

- fortkeep never runs `sudo`. It gives the person the exact command to type in the Terminal app.
- Scripts the person runs around admin steps (`checks/baseline.sh accept`, `checks/managed-settings.sh`) verify the
  copy's integrity before they load anything else.
- `checks/managed-settings.sh` prints the files BL-AI-04 installs as root from the verified release, not from the
  working folder.

## Stated limits

- The guards are hooks, not a sandbox. They hold only while the agent program runs them.
- Codex runs them only after the person trusts the folder's hooks; OpenCode skips its plugin when started with
  `--pure`; other agents have none. Without them nothing is guarded, and no fix should run.
- Anything running as the person's user can change fortkeep's files, approvals and results.
- A first install trusts the pins on `main` or in the tap repo; a plain clone trusts `main` as it is that day, until
  its first `checks/update.sh`.
- A check reports only what it can read. A folder hidden by macOS privacy settings gives ERROR, not PASS.
- The repo sweep and the git scan hook find known campaigns by their indicators; a new campaign passes until its
  indicators are added.

## Known limits

- **The git scan hook's push check** stops your own `git push`. Malware that pushes by itself with `--no-verify`, or
  with a git older than 2.54, skips it, and a push the check can't finish within its time limit goes ahead.
- **Development-session guards** are pattern matching: they miss commands built from globs, names assembled from
  pieces, and shadowed shell functions.
- **The ready-made agent guard** (`templates/agent-guard.sh`) is pattern matching too, with the same gaps. It also
  refuses some harmless commands: a quoted separator next to a protected path, `sed` with a backslash, and Bash
  commands over 64 KB.
- **The terminal check** that keeps `checks/baseline.sh accept` for the person, and lets them run `checks/accept.sh`
  and `checks/private.sh add` without a token, is a tripwire: a renamed terminal binary, or a process that leaves the
  terminal's process tree, gets past it.
- **The process-tree check** counts an agent started by another of the same kind, with no shell between, as one
  agent, so the approval hook can't tell `codex exec` started directly by Codex from Codex itself. An npm launcher
  and the agent it starts must count as one, and agents start copies of themselves for their own work (Codex's
  app-server daemon runs `codex app-server` as its child, with the same executable); telling these apart would rest on
  each agent's undocumented process layout. It matters only when the first agent isn't guarded, since a person's
  session refuses starting another agent.
- **The test-suite switch** needs the environment the test helpers set, their marker file in the test's folder, and
  bats's test runner as an ancestor process. An agent config can set the variables and the agent's write tools can
  make the marker, but neither can make a process tree: a person's agent runs only fortkeep's scripts, which descend
  from the agent. It is also refused in the folders that agent may write (`/private/tmp/claude-*`, any `plans`
  folder). The runner is recognised by its script's path, so a launcher that starts the agent under a program at
  that path gets past it; such a launcher is a local change that session start reports.
- **Linked git hooks.** A file in a scanned repo's `.git/hooks` that links outside the repo is still read, to see
  whether it fetches or runs code. Only the rule it matched is printed, never its content.
- **Private folders by spelling.** Some older callers of `fortkeep_is_private`, `fortkeep_walk` among them, compare
  paths by spelling only, so a private folder reached through another spelling of its path may be read.
- **The weekly run** happens while the Mac is busy: OV-TP-02 can time out there, and BL-RC-03 can't read zsh aliases
  there.
- **Signed releases.** No test yet covers refusing a release tag signed with a PGP key instead of an SSH key.
