# BL-OS-07 · Screen locks immediately

**Why:** An unlocked, unattended laptop gives anyone your logged-in sessions: email, GitHub, cloud consoles, password manager.

**Real attack:** An IBM security tester who is paid to break into offices says that with an unattended company laptop he gets access to every document its owner can reach, can send phishing emails as them and can plant files in company folders. ([source](https://ibm.com/think/insights/physical-cybersecurity))

**Check it yourself:** System Settings → Lock Screen → "Require password after screen saver begins or display is turned off".

**How to fix:** set it to Immediately. Habit to go with it: ⌃⌘Q locks the screen whenever you stand up.

**What the agent is doing:** reading the lock delay with `sysadminctl`; it changes nothing.
