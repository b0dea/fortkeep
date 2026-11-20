# BL-AU-02 · A weekly security check runs and is up to date

**Why:** Settings drift: an update resets something, a new tool adds a login item, a hook gets removed. A weekly review that notifies you when something newly fails catches it within days.

**Real attack:** In a 2022 refund scam against US federal staff, attackers used the remote-support tools AnyDesk and ScreenConnect; US agencies note that this kind of software generally doesn't trigger antivirus alerts, so only a regular look at what is installed and running will catch it. ([source](https://www.cisa.gov/ncas/alerts/aa23-025a))

**Check it yourself:** `launchctl print gui/$(id -u)/io.github.b0dea.fortkeep.weekly` shows the job, and `/posture` says your last review was within the week.

**How to fix:** The agent can install it (`fixes/macos/BL-AU-02.sh apply`). Every Wednesday at 10:00 it runs a KnockKnock scan (if installed) and a full review from this repo, then `brew update` and a report of formulae with a vulnerability that has a released fix (it never upgrades). It logs to `~/Library/Logs/fortkeep-weekly.log`, and shows a notification if something newly fails. It runs this repo's own scripts, so update it only with `checks/update.sh`: it refuses to run, notifies you and logs why when tracked files have local changes.

**What the agent is doing:** checking that the job exists and is loaded, and how long ago the weekly job last ran its review.
