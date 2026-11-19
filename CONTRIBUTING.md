# Contributing

For people and AI coding agents changing devward itself. To check your own Mac, start with the
[README](README.md). Taking part means following the [Code of Conduct](CODE_OF_CONDUCT.md).

**AI agents:** read [AGENTS.md](AGENTS.md) too. It is written for the agent guiding a person through a checkup, and
its hard rules still apply while you develop.

## Setup

```sh
brew install mise
mise trust
make install
```

- `mise trust` lets mise read this repo's `.mise.toml`. A fresh clone isn't trusted, and mise ignores it until it is.
- `make install` installs the dev tools pinned in `.mise.toml` and the git hooks. `mise.lock` holds the tools'
  download checksums, except yamllint's, which mise can only lock by version.
- The tools: bats runs the tests, shellcheck and yamllint lint the shell and YAML, yq compiles the controls, gitleaks
  scans for secrets, lefthook installs the git hooks, and uv installs yamllint with its own pinned Python.
- Node 22 or later runs the OpenCode plugin's tests; without it they skip.
- After changing `.mise.toml`, run `make lock` and commit `mise.lock` with it.

**Without mise:** `brew install bats-core shellcheck yamllint gitleaks lefthook yq`, then `make hooks`. The Makefile
then uses whatever is on your PATH, so versions can differ from the pins.

**Git hooks:** pre-commit refuses a commit on `main` and runs the leak scans; pre-push runs `make push-check`. If your
global git config sets `core.hooksPath`, `make hooks` warns and installs nothing, since lefthook would write into
that shared folder. Run `make ci` before you push instead.

**Start your agent with `DEVWARD_DEV=1`** (for example `DEVWARD_DEV=1 claude`), after creating the marker once
yourself in the Terminal app: `mkdir -p ~/.config/devward && touch ~/.config/devward/dev`. Without both the guards
treat the session as a person's checkup and refuse edits to the repo, so a person's agent can't change the guards,
checks or fixes that later run without a prompt; the marker is a file no person's session can write.

`make` alone lists the targets. How each agent loads the skills and guards is in [docs/agents.md](docs/agents.md);
what's left to build is in [docs/ROADMAP.md](docs/ROADMAP.md).

## Runtime rules

Everything under `checks/`, `fixes/`, `summary/` and `.claude/hooks/` runs on people's Macs:

- macOS's own bash 3.2 and stock tools, plus `jq` (stock since macOS 15) and `perl`; `python3` only for the repo
  scanner, `fixes/files/git-scan-new-files`.
- `make test-stock` runs the tests with stock tools first on PATH; `TESTS=tests/x.bats` runs one file. An agent
  shouldn't set `PATH=…` itself: the development guard refuses it.
- Both run the test files side by side, four at a time (`JOBS=2 make test` for fewer, `JOBS=1` for plain bats
  output). Tests inside one file still run in order, so a test must never depend on another file's state.

## Verification

```sh
make ci
```

It runs lint, the controls check, the tests (also with stock tools) and the scans. Run it before you open a pull
request, and paste its last lines there. `make push-check` is the same without the tests.

CI (`.github/workflows/ci.yml`) runs the same steps on GitHub: lint, the controls check and the scans on Linux, the
tests on macOS. `ci-ok` is the one required check. The payload scan runs devward's own malware scanners over every
push.

On a Mac whose endpoint security (EDR) kills the browser wallet-extension check, `tests/br.bats` fails with exit
code 137. That is the EDR stopping the check, not a test failure; CI runs it on clean runners.

## Add a control

1. **Define it** in `controls/baseline.yaml`, `controls/gold.yaml` or `controls/overlays/<name>.yaml`: an ID such as
   `BL-OS-01` (reuse the area code of the controls nearest it), a title, layer, level, risk, the check, lesson and
   fix paths, and `fix_needs_admin`. A baseline control cites its section of `controls/baseline-source.md` as
   `source: "§N"`. An overlay file is a map, not a list: `title` and `pick_if` (what the set-up question shows) and
   `controls`, the list of its controls. Then `make build`; `make controls-check` fails while `controls/controls.json` is stale or a field
   is wrong.
2. **Write the check**, `checks/macos/<ID>.sh`:
   - it sources `checks/lib/common.sh` and prints one result with `devward_result <ID> <STATUS> <evidence> [note]`,
     where STATUS is PASS, FAIL, NA or ERROR, then exits 0. ACCEPTED is applied by `checks/run.sh`, never by a check;
   - it finishes within its timeout: the control's `timeout` field, or `checks/run.sh`'s default. An overrun is
     recorded as ERROR;
   - it reads system files through `devward_path`, so tests can point `DEVWARD_SYSROOT` at a fake root;
   - it walks folders with `devward_walk` and skips any path `devward_is_private` names;
   - it never uses the network, and never prints a secret's value: counts, lengths or fingerprints only.
3. **Write the lesson**, `teach/<ID>.md`: a `# <ID> · <title>` heading and the labels **Why:**, **Real attack:**,
   **Check it yourself:**, **How to fix:** and **What the agent is doing:**. `tests/lessons.bats` fails without them.
4. **Test it** in `tests/`: `load helpers`, `setup_env`, and `stub <command> '<bash body>'` to fake each command the
   check runs. One test per behaviour, including the ERROR paths.
5. **Optionally, a fix**, `fixes/macos/<ID>.sh apply|undo`, only where it is safe to automate:
   - it sources `fixes/lib/fix.sh` and calls `fx_require_approval` first;
   - it backs up every file before writing it (`fx_backup`), seals the result (`fx_seal`), undoes with `fx_restore`
     and logs with `fx_log`;
   - exit codes: 0 done, 2 usage, 3 a manual step for the person (`MANUAL:`), 4 no approval, 5 nothing to undo, 6
     undo stopped because the files changed after the fix;
   - add its `prefix_rule(... decision="prompt" ...)` line to `.codex/rules/devward.rules`, so Codex asks before it
     runs. `tests/agents.bats` fails without it.

## Indicators and markers

- **Malware markers only as fragments.** Antivirus tools such as Microsoft Defender quarantine any file that holds a
  whole marker, so code and tests join markers from pieces at runtime. `ci/markers.b64` holds the full ones, and the marker scan fails if a
  tracked file contains one.
- **Every indicator needs a public source.** Put the link beside it and in the pull request; an indicator without
  one is not merged.

## Field notes

- Never run `mdatp config …`: it hangs on managed Macs. Read state with `mdatp health --field <name>` only.
- Tamper protection `block` stalls tools that toggle Defender settings. LuLu blocks new programs until approved.
  KnockKnock needs Full Disk Access.
- Test git hooks only in throwaway repos: a checkout test can detach a real working tree.

## Commits

- Commit on a branch; the pre-commit hook refuses a commit on `main`.
- Subject: what is now true, in the imperative, under 72 characters. Body only when the why isn't obvious.
- Stage explicit paths and review the diff before committing. Never bypass the hooks; fix the cause.
- Nothing identifying: no employer or client names, real usernames, hostnames or paths from your Mac, in files or
  commit messages.

## Pull requests

One concern per pull request.

- **A bug fix lands with a test that fails without it.** Say how you saw it fail.
- **Paste real output, not a summary**, and say what you didn't run.
- Documentation for a behaviour change goes in the same pull request.
- Open an **issue first** for a new control, a change to a control's level, or a new command.

## Reporting issues

Use the issue forms. A check that gives the wrong result has its own form. Never paste `results.json` as it is: it
holds file and folder names from your Mac. **Never report a vulnerability in a public issue**; follow
[SECURITY.md](SECURITY.md).

## What will not be accepted

- **A check that changes the Mac**, uses the network or prints a secret.
- **A fix with no backup, seal or undo**, or one that runs without an approval.
- **A weakened test**: skipped, deleted, or an assertion edited to match current behaviour, or a fix that works by
  disabling a check.
- **A whole malware marker** in any file, or an indicator with no public source.
- **A dependency at runtime** beyond stock macOS tools.
- **Speculative abstraction**: a setting with no second caller, handling for states that cannot occur.
- **A hand-edited `controls/controls.json`.** Edit the YAML and run `make build`.

## Maintainers

- **Only a maintainer, never an agent,** writes their global git config, runs `make install` and `brew install`, and
  runs `checks/baseline.sh accept`.
- **`make scan-private`** fails if a tracked file contains a term from your own list of names you never want
  committed, such as employer or client names: `~/.config/devward/denylist`, one per line. It needs that list, so
  contributors' gates leave it out.
- **Releases.** People's Macs run signed releases, not `main`. On `main`, `make release VERSION=v1.2.3` runs `make ci`
  and `make scan-private`, signs the tag with your SSH signing key and keeps it only if copies would accept it. Publish
  it with `git push origin main v1.2.3`. The release workflow then checks the signature again, runs `make ci` and
  publishes the GitHub release; it signs nothing and holds no secrets.
- **Maintainer keys** live in `.github/allowed_signers`. Add or remove one in a release that a currently listed
  maintainer signs: copies only accept a release signed by a key they already list.

## Governance

One maintainer, [@b0dea](https://github.com/b0dea), reviews and merges everything and owns every path in
[CODEOWNERS](.github/CODEOWNERS). There is no second reviewer and no on-call, so review can stall, and no response
window is promised except for [security reports](SECURITY.md). The license is MIT, so a fork is always available.
Before 1.0, controls may tighten and commands may change between releases. Small, tested changes that follow the
rules above are the most likely to merge; propose a larger one in an issue first.
