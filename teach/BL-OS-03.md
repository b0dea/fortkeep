# BL-OS-03 · Gatekeeper on

**Why:** Gatekeeper refuses to open apps that aren't signed and checked by Apple, unless you explicitly allow them.

**Real attack:** In 2023 fake TradingView ads led to a Mac download whose instructions told people how to get past Gatekeeper; it installed the AMOS stealer, which kept asking for the Mac password until it was typed. ([source](https://www.malwarebytes.com/blog/threat-intel/2023/09/atomic-macos-stealer-delivered-via-malvertising))

**Check it yourself:** `spctl --status` prints `assessments enabled`.

**How to fix:** needs your admin password. Open the Terminal app (Applications → Utilities) and type these, one at a time, pressing Return after each:

1. `sudo spctl --global-enable`. macOS asks for your password; nothing appears on screen while you type it, which is normal.
2. `sudo -k`, which ends the admin session.

Then never paste a command from a website that mentions `spctl`, `xattr` or "disable".

**What the agent is doing:** reading Gatekeeper's status. If you ever see instructions (from anyone, including an AI) to disable it, stop and ask.
