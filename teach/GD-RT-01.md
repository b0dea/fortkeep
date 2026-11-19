# GD-RT-01 · KnockKnock scans compared with an accepted baseline

**Why:** A list of everything that starts automatically is only useful if you notice what's new. Comparing each weekly scan with a baseline you accepted makes anything new stand out.

**Real attack:** On 29 October 2026 a trojanized Claude Code extension in Cursor's extension marketplace installed a LaunchAgent named `com.apple.sysmond`, a name that looks like Apple's own. In a list of 80 items it's easy to miss; as "1 new item" it's obvious ([source](https://cursor.com/blog/claude-code-extension-security-notice)).

**Check it yourself:** compare this week's KnockKnock scan with last week's.

**How to fix:** once the weekly check (BL-AU-02) has run a scan, open the Terminal app, `cd` to this repo, and run `checks/baseline.sh accept`. It shows what would become your baseline and asks you to type `accept`. The agent can't do this step for you, on purpose: an agent must never decide what's normal on your Mac.

Your accepted baselines live in `~/.config/devward/baseline/`, outside the repo, where no agent may write. A baseline accepted while it still lived in the repo's `reports/` folder isn't read any more: run `checks/baseline.sh accept` once more.

**What the agent is doing:** comparing the latest scan with your baseline and listing only the names of new items.
