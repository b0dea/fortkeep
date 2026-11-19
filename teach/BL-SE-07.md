# BL-SE-07 · SSH keys rotated within the last year

**Why:** Old keys have had years to end up in backups, old laptops, transcripts and logs. Rotating on a schedule, not after an incident, limits what a forgotten copy is worth.

**Real attack:** The May 2026 node-ipc malware copied every private key matching `~/.ssh/id*` on the machine, old ones included, so any old key that still works somewhere is worth stealing until it is rotated. ([source](https://semgrep.dev/blog/2026/not-your-ipc-but-node-ipc-npm-hit-again-with-supply-chain-attack-but-this-time-its-not-a-worm))

**Check it yourself:** `ls -l ~/.ssh` and look at the dates of the private key files.

**How to fix:** create a new key (in your SSH agent from BL-SE-01, or `ssh-keygen -t ed25519`), add it where the old one was used (GitHub, servers), then remove the old one from those places and delete it.

**What the agent is doing:** reading the dates of the key files in `~/.ssh`.
