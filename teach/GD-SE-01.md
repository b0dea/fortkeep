# GD-SE-01 · GitHub token has an expiry date

**Why:** A token that never expires keeps working wherever a copy ends up. An expiry limits how long a stolen copy is worth anything.

**Real attack:** GitGuardian retested secrets it had found working in public repositories in 2022: four years later, 64% of them still worked ([source](https://www.gitguardian.com/state-of-secrets-sprawl-report-2026)).

**Check it yourself:** on GitHub → Settings → Developer settings → Fine-grained tokens, your token shows an expiry date.

**How to fix:** create a fine-grained token with an expiry (90 days is common), `gh auth login --with-token`, and put a reminder in your calendar to renew it.

**What the agent is doing:** asking GitHub, once, for the expiry header of the token gh uses. It keeps only the response headers, never the token or your account details.
