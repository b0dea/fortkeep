# BL-AI-01 · The agent's own shell finds npm at the Safe Chain shim

**Why:** Agents are suggestible and run with your credentials. A line of text in a README is enough to make one run an install. Safe Chain only stops that if the agent's own shell reaches the shims first.

**Real attack:** In May 2026 researchers showed that a booby-trapped README in a public repo, written as an error-fixing guide, made the Cursor coding agent print the developer's secret keys and send them to the attacker; the victim only had to point the agent at the repo. ([source](https://www.0din.ai/blog/stealing-environment-keys-from-cursor-ide-with-a-malicious-readme))

**Check it yourself:** ask the agent to run `/usr/bin/which npm` and `npm install --no-save safe-chain-test`. The first must print the shim; the second must be refused.

**How to fix:** fix BL-SC-02 and BL-SC-03, then quit the agent and start it again: it keeps the PATH it started with. Start it from the fortkeep folder as before and type `/fix` (in Codex, `$fix`); it checks the Mac again first.

**What the agent is doing:** asking where npm is in the shell this very review runs in, which is the agent's own.
