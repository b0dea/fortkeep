# BL-RC-02 · Global git hook scans what a clone, pull or checkout brings in

**Why:** A poisoned repo doesn't need `npm install`. Code hidden after a long run of spaces in a config file, a `.vscode/tasks.json` that runs when the folder opens, or new agent hooks all run the next time you start a dev server, open the folder or start an agent. The attackers change their markers every few weeks, so a scanner copied months ago misses the new ones.

**Real attack:** The North Korea-linked PolinRider campaign appends hidden code after a run of blank space in config files such as `postcss.config.mjs` and `tailwind.config.js`, so it is out of sight when you open the file. OpenSourceMalware counted 1,951 infected repositories by 11 April 2026. ([source](https://github.com/OpenSourceMalware/PolinRider), [source](https://opensourcemalware.com/blog/polinrider-is-a-b-testing-its-way-past-your-detections))

**Check it yourself:** `git config --global --get-regexp '^hook\.'` lists hooks for post-checkout, post-merge and post-rewrite, and `git --version` is 2.54 or newer. From this repo's folder, `cmp ~/.local/bin/git-scan-new-files fixes/files/git-scan-new-files` prints nothing when your scanner is up to date.

**How to fix:** The agent can install it (`fixes/macos/BL-RC-02.sh apply`): one script in `~/.local/bin` and six lines in your global git config, with a backup and an undo. The same fix replaces a scanner that is out of date. It only reads files and warns (with a notification for serious findings); it never blocks or deletes anything. It also warns when this repo's own `.claude/settings.json` changes in an update. That's expected here, and the same warning on someone else's repo is your cue to look before opening it in an agent.

**What the agent is doing:** reading your global git config and comparing the installed scanner with this repo's copy. Nothing changes.
