# BL-RT-03 · Outbound firewall (Little Snitch or LuLu) running

**Why:** Stolen data has to leave your Mac. An outbound firewall asks before a program connects somewhere new, and its blocklists stop known bad hosts.

**Real attack:** In July 2026 two trojanized npm packages (since removed) looked up their attacker's server address from a public Ethereum blockchain transaction, so there was no fixed address to blocklist; an outbound firewall at least shows the unexpected connection. Honest caveat: if your terminal and editor are allowed to connect anywhere, it won't flag a script started from them. ([source](https://thehackernews.com/2026/08/trojanized-npm-packages-decode-c2-ip.html))

**Check it yourself:** the Little Snitch or LuLu icon is in the menu bar and it's turned on.

**How to fix:** buy Little Snitch (about €59, once) and enable the URLhaus, HaGeZi and NoCoin blocklists, or install LuLu (free) from objective-see.org. LuLu blocks new programs until you approve them, so expect a few prompts at first.

**What the agent is doing:** checking that one of them is installed and running.
