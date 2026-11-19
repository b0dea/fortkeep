# Security policy

## Supported versions

Fixes land on the latest release only; updating to it is the fix. There is no long-term support branch and no
backporting.

## Reporting a vulnerability

**Never report a vulnerability in a public issue, pull request or discussion.** A public fix whose diff or message
explains the problem is a disclosure too.

Report it privately through GitHub's private vulnerability reporting: open the repository's
[**Security** tab](https://github.com/b0dea/devward/security) and choose **Report a vulnerability**. There is no
security email address.

A useful report gives what an attacker can do, the smallest reproduction you can make, the devward version and macOS
version involved, which coding agent ran it, and whether you intend to publish. Leave out anything from your own Mac
that you wouldn't publish: real paths, usernames, `results.json` as it is.

## What to expect

There is one maintainer and no on-call rotation, so these windows are in days:

| | |
|---|---|
| Acknowledgement | within 7 days |
| First assessment: is it a vulnerability, and how bad | within 14 days of acknowledgement |
| Fix | no fixed window; confirmed high severity is worked on next, lower severity ships with the next release |

With no acknowledgement after 14 days, send the report again. You will be told the conclusion, including why when it
is not a vulnerability.

## Disclosure

Coordinated. Once a fix is released the advisory is published, crediting the reporter unless they ask otherwise. If
no fix has shipped **90 days** after acknowledgement, you are free to publish; ask sooner if you have a deadline.

## Scope

devward runs on people's Macs, beside a coding agent, and some of what it does there runs later without a prompt.
What it promises, and what it doesn't, is in the [threat model](docs/threat-model.md). In scope is anything that
breaks those promises:

- getting past the session guards, so the agent in a person's session runs, reads or writes something they refuse;
- forging an approval, so a fix runs without the person's own `Apply <ID>` or `Undo <ID>`;
- a fix or an undo that loses the person's data, such as an edit to a start-up file that undo then overwrites;
- reading, listing or describing a folder the person marked private;
- printing a secret's value, to the screen, a report or the agent;
- getting a copy to run a release that a listed maintainer didn't sign, or to treat changed files as a signed
  release;
- getting the installer (`install.sh`) or the Homebrew formula to install anything but the release they pin.

Out of scope:

- something already running as the person's macOS user outside a devward session. It can change any file that user
  can, devward's included; the threat model says so;
- vulnerabilities in the coding agents, Safe Chain or the other tools devward checks for. Report those upstream, and
  tell us as well if devward should check for them.

**Not security reports:** a check that gives the wrong result, or an indicator that flags something harmless. Open
an ordinary issue with the [wrong check result](https://github.com/b0dea/devward/issues/new?template=wrong-result.yml)
form.

## Verifying a release

Releases are version tags that a maintainer signs with an SSH key listed in
[`.github/allowed_signers`](.github/allowed_signers). `checks/update.sh` refuses any other tag. To check one by hand,
in a devward folder:

```sh
git fetch --tags origin
git -c gpg.ssh.allowedSignersFile=.github/allowed_signers verify-tag v0.1.0
```

It prints `Good "git" signature for <maintainer>` and the key's fingerprint. A release tag's message is
`b0dea/devward <tag>`; `checks/update.sh` refuses a tag whose message names another repo or another tag.

Compare the listed keys with the ones the maintainers publish on GitHub, rather than trusting the file alone:

```sh
awk '!/^#/ && NF { print $3, $4 }' .github/allowed_signers | ssh-keygen -lf -
```

Each fingerprint should match a signing key at `https://api.github.com/users/<maintainer>/ssh_signing_keys` (pipe
that key through `ssh-keygen -lf -` the same way).
