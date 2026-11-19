# OV-ME-03 · Behaviour monitoring as your organisation's IT or security team wants it

**Why:** Behaviour monitoring catches malware by what it does, not by its signature. Some organisations turn it off on developer Macs for performance; that's their decision, not yours or the agent's.

**Real attack:** In February 2026 Atomic macOS Stealer spread through OpenClaw agent skills that VirusTotal rated benign, but what they installed behaved recognisably: it read the Apple keychain and the stored data of 19 browsers, then uploaded them to the attacker's server ([source](https://www.trendaisecurity.com/en-us/resources-insights/trendai-security-blog/malicious-openclaw-skills-used-to-distribute-atomic-macos-stealer)).

**Check it yourself:** for Defender, `mdatp health --field behavior_monitoring` prints `"enabled"` or `"disabled"`. For other products, ask your organisation's IT or security team.

**How to fix:** if it's off, ask your organisation's IT or security team whether that's intended. Don't change it yourself. If they want it off, tell the agent and it records that as your decision (ACCEPTED).

**What the agent is doing:** for Defender, reading one health field. For other products, nothing it can read safely, so the result is "doesn't apply" with a note.
