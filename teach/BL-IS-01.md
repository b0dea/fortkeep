# BL-IS-01 · A VM or container tool for untrusted code

**Why:** Interview take-homes, "please review my code" zips and random GitHub projects are how developer Macs get owned. Run them in a throwaway VM or container with only that folder mounted: no home folder, no keys, no logins. The baseline makes never running them on your main account a MUST.

**Real attack:** North Korean attackers pose as recruiters and send developers a take-home coding test hidden with malware that can steal credentials, crypto wallets and API tokens; a November 2026 report on the PolinRider campaign describes the same lure, and Atlassian advises running such tests only in an isolated environment. ([source](https://www.atlassian.com/blog/how-we-build/disrupting-contagious-interview), [source](https://abnormal.ai/blog/polinrider-fake-coding-assignments))

**Check it yourself:** OrbStack, UTM, Docker Desktop, Colima or similar is installed, and you actually use it for code you didn't write.

**How to fix:** install OrbStack (free for personal use; paid for work) or UTM (free). Use dev containers for repos you work on often but didn't write, and a separate macOS user account for anything truly sketchy.

**What the agent is doing:** looking for known VM and container apps and commands.
