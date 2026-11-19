# BL-RC-01 · VS Code and Cursor automatic tasks off

**Why:** A repository can include a task set to run the moment you open its folder. With automatic tasks allowed, opening a folder is enough to run its code.

**Real attack:** In 2026 Microsoft reported North Korea-linked "fake job interview" campaigns that send developers a coding-test repo; once the developer trusts the folder, VS Code runs the repo's task file, which fetches a backdoor, and no `npm install` is needed. One variant's stealer took browser logins and, on macOS, the iCloud Keychain database. ([source](https://microsoft.com/en-us/security/blog/2026/03/11/contagious-interview-malware-delivered-through-fake-developer-job-interviews), [source](https://thehackernews.com/2026/03/north-korean-hackers-abuse-vs-code-auto.html))

**Check it yourself:** in VS Code, press Cmd+Shift+P, choose "Preferences: Open User Settings (JSON)" and look for the line `"task.allowAutomaticTasks": "off",`. The Settings screen isn't enough: it shows "off" when that's only the editor's default, and a later version can change the default. Repeat for each profile and in Cursor.

**How to fix:** The agent can set it in every settings file for you (`fixes/macos/BL-RC-01.sh apply`), with a backup and an undo. A settings file that contains comments can't be edited safely by a script; then open it as above and add `"task.allowAutomaticTasks": "off",` on its own line just after the opening `{`, and save.

**What the agent is doing:** reading your editor settings files for this one setting. To change them it will ask first, back them up, and log the change.
