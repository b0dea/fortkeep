# BL-OS-06 · Sharing services off

**Why:** Each sharing service listens for connections from the network. Services you don't use are doors left unlocked.

**Real attack:** In August 2026 attackers broke into Macs whose Screen Sharing port was reachable from the internet, using a flaw (CVE-2026-65400) that let them in without a password, and planted a crypto miner; Apple's fix shipped on 6 August. ([source](https://thehackernews.com/2026/08/apple-macos-screen-sharing-flaw.html))

**Check it yourself:** System Settings → General → Sharing: everything off unless you use it this week. General → AirDrop & Handoff: AirPlay Receiver off.

**How to fix:** switch those off in the same panels. Nothing breaks: you can turn one back on the day you need it.

**What the agent is doing:** listing which network ports are open (not what's sent over them) and reading the AirPlay Receiver setting.
