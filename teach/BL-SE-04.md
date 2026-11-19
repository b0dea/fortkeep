# BL-SE-04 · GitHub CLI uses a fine-grained token

**Why:** `gh auth login` gives a classic token with full `repo` access (often `workflow` and `admin:org` too), and any program running as you can read it with `gh auth token`. A fine-grained token is limited to the repos and permissions you pick, and it expires.

**Real attack:** MITRE records that the Shai-Hulud worm (2025) used stolen GitHub access tokens to reach victims' accounts and changed private repositories to public. ([source](https://attack.mitre.org/software/S9008/))

**Check it yourself:** `gh auth token | cut -c1-11` prints `github_pat_` for a fine-grained token. `gho_` or `ghp_` means classic. Print only those first characters, never the whole token.

**How to fix:** on GitHub → Settings → Developer settings → Fine-grained tokens, create a token scoped to the org and repos you need, with an expiry, then `gh auth login --with-token` and paste it there. Keep cloud CLIs on short-lived sessions too (BL-SE-05). Use passkeys or hardware keys (YubiKey) for GitHub, Google and 1Password sign-in where you can.

**What the agent is doing:** asking gh for its token and looking only at its first characters, in memory. The token is never printed or saved.
