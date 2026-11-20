# BL-SC-02 · Safe Chain shims first on PATH in every shell type

**Why:** Safe Chain only protects commands that reach its shims first. Scripts, editors and agents start shells that read different start-up files than your Terminal does, so one missing line leaves them unprotected. One extra line does too: a later line in `~/.zshrc` that puts another folder first (a Homebrew Python's `libexec/bin`, say) puts the real `pip`, `pip3` and `python3` ahead of the shims in every Terminal window and in everything started from it (Makefiles, npm scripts, `sh -c`).

**Real attack:** In August 2025 malicious Nx packages ran a script at install time that tried to use the Claude and Gemini command-line tools on the victim's machine and uploaded what it found to a public GitHub repository; the bad versions were live for about four hours. Any `npm install` that reaches the real npm, from an agent's shell or a script, gets no protection. ([source](https://nx.dev/blog/s1ngularity-postmortem))

**Check it yourself:** each of these should print a path in `.safe-chain/shims`: `zsh -lc '/usr/bin/which npm pip3'`, `zsh -c '/usr/bin/which npm pip3'`, `zsh -ic '/usr/bin/which npm pip3'`, `env -i HOME=$HOME /bin/zsh -lc '/usr/bin/which npm pip3'`, and if you use bash, `bash -lc …` and `bash -c …`. The check asks about every command Safe Chain has a shim for (`ls ~/.safe-chain/shims`).

**How to fix:** The agent can do it (`fixes/macos/BL-SC-02.sh apply`). It adds one small file that puts the shims first and pins the age gate at 168 hours, and loads it from `~/.zshenv`, `~/.zshrc` and `~/.zlogin` (and your bash start-up files if you have them), with a backup and an undo. If a line after it changes PATH again, move the line marked `fortkeep` to the very end of that file.

**What the agent is doing:** starting each kind of shell once, your interactive one included, and asking where each Safe Chain command is. Nothing is installed or changed.
