# OV-VL-01 · varlock installed from its official tap and pinned

**Why:** varlock keeps secret values out of the agent's context. The agent reads `.env.schema`, which holds only names and markers such as `@sensitive`, and runs commands as `varlock run -- <cmd>`: varlock puts the values into that one command's environment and masks them in its output, so they never land in the transcript. Values stay encrypted at rest, with a key in the Secure Enclave behind Touch ID, or in the Keychain. That makes varlock a program that can read every secret, so it has to be the real one, and it mustn't change under you.

**Real attack:** From January to April 2021 attackers altered Codecov's Bash Uploader, a script that runs where CI secrets live, so that it sent those environment variables to their server; a customer caught it because the download no longer matched its published checksum. A weekly `brew upgrade` would install a hijacked release of a secrets tool without anyone looking ([source](https://about.codecov.io/security-update/)).

**Check it yourself:** `brew list --formula --full-name | grep varlock` shows `dmno-dev/tap/varlock`, and `brew list --pinned` lists `varlock`. That formula downloads varlock's own GitHub release and checks it against a sha256 written in the formula. The macOS binary is only ad-hoc signed: no Developer ID, not notarized, so macOS can't vouch for who built it. The tap's checksum is the check you have.

**How to fix:** in Terminal, `brew install dmno-dev/tap/varlock`, then `brew pin varlock`. To update, read the release notes, `brew unpin varlock`, `brew upgrade varlock`, `brew pin varlock`. If you use OpenCode, its default rule hides `*.env.*` files, `.env.schema` included: add `"*.env.schema": "allow"` to its read permissions so the agent can see the names.

**Limits:** varlock stops values leaking by accident. A script written to send a value somewhere can still do it inside `varlock run`; only a sandbox contains that.

**What the agent is doing:** finding varlock from a login shell, and asking Homebrew which formula installed it and whether it's pinned. It changes nothing.
