# BL-AU-01 · A weekly update job runs

**Why:** Security tools and packages only help while they're current. A weekly job that upgrades your Homebrew packages keeps that from depending on memory.

**Real attack:** US government agencies reported that in 2022 attackers exploited older, already-fixed software flaws more often than new ones, because many organisations hadn't installed the fixes. ([source](https://www.cisa.gov/news-events/cybersecurity-advisories/aa23-215a))

**Check it yourself:** `launchctl list | grep -i weekly` shows your job, and its log shows a recent run.

**How to fix:** fortkeep's own weekly security check (BL-AU-02) doesn't count here: it runs `brew update` and tells you when a formula has a vulnerability with a released fix, but it never upgrades anything. This control needs a job that runs `brew upgrade` itself.

Save this as `~/.local/bin/weekly-update.sh` and make it executable (`chmod +x`):

    #!/bin/zsh
    export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
    { date; brew update && brew upgrade && brew vulns --fix-available; } 2>&1

Then create a LaunchAgent in `~/Library/LaunchAgents` that runs it every Monday (the agent can write the plist with you), and load it with `launchctl bootstrap gui/$(id -u) <plist>`.

**What the agent is doing:** looking through your own LaunchAgents for a weekly job whose command or script runs `brew upgrade`, leaving out fortkeep's own weekly check, and checking that it's loaded.
