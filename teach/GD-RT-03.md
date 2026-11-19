# GD-RT-03 · No live malware process, C2 connection or known backdoor file

**Why:** The other checks look at settings and files. This one looks for malware that is already running: a hidden loader process, a connection to an attacker's server, or a backdoor left behind.

**Real attack:** In November 2026 hijacked npm packages started `node -i` in the background, with no terminal, and piped their loader into it. On 29 October 2026 a trojanized Claude Code extension added a LaunchAgent named `com.apple.sysmond`, dropped a script at `~/.config/.smt`, and added its own SSH key, labelled `svc-telemetry`, to `~/.ssh/authorized_keys` ([source](https://www.sonatype.com/blog/polinrider-loader-reappears-in-hijacked-npm-packages), [source](https://cursor.com/blog/claude-code-extension-security-notice)).

**Check it yourself:** `ps -axo pid,tty,command | grep -E 'node|python'` (`??` in the TTY column means no terminal); `lsof -nP -iTCP -sTCP:ESTABLISHED`; `ls -la ~/Library/LaunchAgents ~/.config/.smt*`; `grep svc-telemetry ~/.ssh/authorized_keys`.

**How to fix:** don't try to clean it up yourself, and don't type passwords until it's dealt with: type `/if-red` and follow it. A note on a PASS (a short inline script, a temp folder that exists) is worth a look but isn't malware on its own.

**What the agent is doing:** listing node and python processes (name, terminal, age and working folder; never their command line), your own network connections, a few known backdoor file names, your shell and npm start-up files, your crontab, LaunchAgents and LaunchDaemons, and the temp folders loaders stage in. It reports file names and line numbers, never the lines themselves. Nothing changes.
