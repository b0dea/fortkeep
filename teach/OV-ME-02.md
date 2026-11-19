# OV-ME-02 · Tamper protection on (block, for Defender)

**Why:** With tamper protection on, malware (or a well-meaning agent) can't switch the protection off or change its settings.

**Real attack:** Switching off or tampering with security tools is a standard attacker step, listed in MITRE ATT&CK as a technique of its own with macOS malware among the examples. With Defender's tamper protection in block mode, attempts to stop, change or uninstall it fail and are logged ([source](https://attack.mitre.org/techniques/T1685/), [source](https://learn.microsoft.com/en-us/defender-endpoint/tamper-protection-macos-configure)).

**Check it yourself:** for Defender, `mdatp health --field tamper_protection` prints `"block"`. For other products, look in the product's settings or ask your organisation's IT or security team.

**How to fix:** your organisation's IT or security team sets this through device management; tell them if it isn't on. Expect tools that try to change the protection's settings to stall: that's working as intended.

**What the agent is doing:** for Defender, reading one health field (never `mdatp config`, which hangs on managed Macs). For other products there's no safe way to read it, so the result is "doesn't apply" with a note to ask the security team.
