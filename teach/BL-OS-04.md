# BL-OS-04 · System Integrity Protection on

**Why:** SIP stops anything, even with admin rights, from changing core macOS files. Malware that can't touch the system can't hide in it.

**Real attack:** In 2021 Microsoft found a macOS bug, "Shrootless", that let an attacker get around SIP and then install a rootkit (malware that hides deep in the system) or overwrite system files; Apple fixed it in October 2021. Microsoft calls SIP the Mac's "last line of defense" against malware. ([source](https://www.microsoft.com/security/blog/2021/10/28/microsoft-finds-new-macos-vulnerability-shrootless-that-could-bypass-system-integrity-protection/))

**Check it yourself:** `csrutil status` prints `System Integrity Protection status: enabled.`

**How to fix:** SIP can only be turned on from macOS Recovery:
1. Shut down. On Apple silicon, press and hold the power button until "Loading startup options" appears, then choose Options. On Intel, restart holding ⌘R.
2. Utilities → Terminal, type `csrutil enable`, press Return.
3. Restart.
4. To come back afterwards: open the Terminal app, type `cd` and a space followed by the devward folder, press Return, start your coding agent as before and type `/fix` (in Codex, `$fix`). It checks the Mac again first.

**What the agent is doing:** reading SIP's status. The agent can't reach Recovery; you do these steps yourself and tell the agent when you're back.
