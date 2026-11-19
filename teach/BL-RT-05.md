# BL-RT-05 · Endpoint protection or antivirus running

**Why:** Endpoint protection watches behaviour, not just files, and can stop a stealer while it runs. It does that through a macOS system extension, so an installed app whose extension isn't running protects nothing.

**Real attack:** In 2025 an AMOS stealer campaign, run by a person pasting a command into Terminal, went on to read browser logins, wallet files and the keychain database and upload them as a zip, which is the kind of behaviour endpoint protection watches for. ([source](https://www.trendmicro.com/en_gb/research/25/i/an-mdr-analysis-of-the-amos-stealer-campaign.html))

**Check it yourself:** in Terminal, `systemextensionsctl list` should show your security product (Defender, Falcon, SentinelOne, …) ending in `[activated enabled]`.

**How to fix:** this usually comes from your organisation's IT or security team; ask them. If the app is installed but not running, open it and finish its setup: macOS may be waiting for you to allow its extension in System Settings > General > Login Items & Extensions. Exclude repo and cache folders from *signature* scanning if builds are slow, but never from the behavioural engine. If you have none and don't need one, tell the agent and it records that as your decision.

**What the agent is doing:** looking for known endpoint-protection apps and commands, and reading `systemextensionsctl list` to see whether one of them is running.
