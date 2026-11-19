# BL-SE-06 · gitleaks runs as a global pre-commit hook

**Why:** A secret committed by mistake can be found by bots within minutes of a push to a public repo. gitleaks stops the commit before it's made, in every repo.

**Real attack:** In the 2023 "EleKtra-Leak" campaign, Unit 42 found the attacker detected AWS keys leaked on public GitHub and used them within about five minutes to launch cryptocurrency-mining servers. ([source](https://unit42.paloaltonetworks.com/malicious-operations-of-exposed-iam-keys-cryptojacking/))

**Check it yourself:** `git config --global --get-regexp '^hook\.'` shows a pre-commit hook running gitleaks.

**How to fix:** The agent can add it (`fixes/macos/BL-SE-06.sh apply`) once gitleaks is installed (`brew install gitleaks`), with a backup and an undo. Run `gitleaks git <repo>` on any repo you inherit, and use git-filter-repo to purge what it finds.

**What the agent is doing:** reading your global git config.
