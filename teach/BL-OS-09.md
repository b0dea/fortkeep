# BL-OS-09 · Unused remote-access tools removed

**Why:** TeamViewer, AnyDesk and RustDesk give someone full control of your Mac. When removed by dragging to the Bin, they leave privileged helpers behind that keep running as root.

**Real attack:** In 2022 help-desk-themed phishing emails got US federal staff to run AnyDesk and ScreenConnect; the attackers then connected to victims' computers and, in a refund scam, altered bank pages on screen to take money. The portable versions needed no administrator rights to run. ([source](https://www.cisa.gov/ncas/alerts/aa23-025a))

**Check it yourself:** look in /Applications, and in /Library/PrivilegedHelperTools and /Library/LaunchDaemons for files with those names.

**How to fix:** open the app and use its own Uninstall option (TeamViewer: Settings → Advanced → Uninstall), or download the vendor's uninstaller. If you do use one for work, tell the agent and it will record that as your decision.

**What the agent is doing:** checking for app and helper names only; it opens nothing.
