# BL-RT-02 · KnockKnock installed

**Why:** KnockKnock lists everything set to start automatically on your Mac, in about 20 places. Run weekly and compared with last week, it shows anything new.

**Real attack:** Apple's developer forums confirm that apps with a privileged helper (a background program with extra rights) install it as a launch daemon, and that there is no automatic removal: dragging the app to the Bin can leave the helper behind. ([source](https://developer.apple.com/forums/thread/66821))

**Check it yourself:** open KnockKnock and run a scan; anything unsigned or unknown deserves a look.

**How to fix:** download KnockKnock from objective-see.org and grant it Full Disk Access (System Settings → Privacy & Security → Full Disk Access). On first run, leave "Include macOS components" and "Start at Login" off and keep update checks on. The weekly check (BL-AU-02) runs it for you and compares results with the baseline you accept (GD-RT-01).

**What the agent is doing:** checking that the app is installed.
