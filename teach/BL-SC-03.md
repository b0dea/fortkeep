# BL-SC-03 · Apps started from the Dock get the Safe Chain shims

**Why:** Apps you open from the Dock or Finder (editors, desktop AI apps) don't read your shell files. They get the PATH that launchd, the part of macOS that starts apps, hands them. Without the shims in it, their built-in terminals and agents call the real npm and pip.

**Real attack:** In August 2025 malicious Nx packages ran a script at install time and were live for about four hours. An `npm install` started from an editor opened via the Dock uses launchd's PATH, so unless the shims are there it gets no age gate or malware feed, even though your Terminal is protected. ([source](https://nx.dev/blog/s1ngularity-postmortem))

**Check it yourself:** open TextEdit from the Dock, then type this in the Terminal app. It prints only TextEdit's PATH, which should start with `…/.safe-chain/shims`:

    ps -Eww -o command= -p "$(pgrep -x TextEdit)" | tr ' ' '\n' | grep '^PATH='

**How to fix:** this needs your admin password and a restart. Open the Terminal app (Applications → Utilities) and type these, one at a time, pressing Return after each:

1. `sudo launchctl config user path "$HOME/.safe-chain/shims:$HOME/.safe-chain/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"` (one line). macOS asks for your password; nothing appears on screen while you type it, which is normal.
2. `sudo -k`, which ends the admin session.
3. Restart the Mac (Apple menu → Restart). The setting takes effect only after a restart.
4. To come back afterwards: open the Terminal app, type `cd` and a space followed by the devward folder, press Return, start your coding agent as before and type `/fix` (in Codex, `$fix`). It checks the Mac again first.
- It applies to every user account on this Mac. If other people log in to this Mac, ask whoever manages this Mac first.
- If you use a Node version manager (nvm, fnm, Volta), its folder isn't in this PATH. Tell the agent, and it will show you how to add it.
- To undo it, type `sudo launchctl config user path "/usr/bin:/bin:/usr/sbin:/sbin"`, then `sudo -k`, and restart.

**Login items:** apps and helpers that start at login are started by launchd as their own jobs, and those jobs don't take this setting: they keep `/usr/bin` first. The check can't tell them apart from apps you opened, so the setting decides the result, and the note names up to five running apps without the shims. Quit one and reopen it from the Dock or Finder, and it has the shims until it next starts at login. If one of them runs `npm` or `pip` for you (a menu-bar tool with shell plugins, say), start it that way after each login.

**What the agent is doing:** reading launchd's stored setting, which decides the result, and the PATH of the apps you have open (only that one value, nothing else from their environment), to name any without the shims. Nothing changes. The agent never runs sudo.
