# BL-RT-01 · BlockBlock installed and running

**Why:** Malware that wants to survive a restart has to install persistence: a LaunchAgent, a login item, a cron job. BlockBlock alerts the moment anything tries, and lets you block it.

**Real attack:** In 2025 Trend Micro analysed an AMOS stealer campaign (spread through fake "cracked" Mac apps) that installs a background job in `/Library/LaunchDaemons` so its hidden backdoor script keeps running after a restart. BlockBlock is built to alert whenever a new persistent component like that is added. ([source](https://www.trendmicro.com/en_gb/research/25/i/an-mdr-analysis-of-the-amos-stealer-campaign.html), [source](https://objective-see.org/products/blockblock.html))

**Check it yourself:** BlockBlock's icon is in the menu bar, and its window shows protection on.

**How to fix:** download BlockBlock from objective-see.org, install it, grant it Full Disk Access when asked, and in its settings turn on Notarization mode, Block Scripts and the ClickFix paste protection.

**What the agent is doing:** checking that BlockBlock is installed and its process is running.
