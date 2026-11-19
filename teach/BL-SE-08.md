# BL-SE-08 · AI-agent transcripts kept out of backups

**Why:** Agent transcripts (Claude Code's `projects` folder, Codex sessions, OpenCode's database) contain everything you pasted, secrets included. Backups copy them to more places.

**Real attack:** In February 2026 Hudson Rock reported an infostealer taking an AI agent's gateway tokens, private keys and memory files from its configuration folder. Agent folders hold secrets, so every extra copy, backups included, is another place to lose them. ([source](https://securityaffairs.com/188097/malware/hackers-steal-openclaw-configuration-in-emerging-ai-agent-threat.html))

**Check it yourself:** `tmutil isexcluded ~/.claude/projects` prints `[Excluded]`.

**How to fix:** `tmutil addexclusion ~/.claude/projects` (and the same for each folder the agent names). Scrubbing old transcripts weekly also helps.

**What the agent is doing:** asking Time Machine whether these folders are excluded.
