# BL-OS-02 · Firewall on with stealth mode

**Why:** The firewall stops other devices on the same network from connecting to services on your Mac. Stealth mode makes the Mac ignore probes, so it is harder to find at all.

**Real attack:** The DarkHotel campaign targeted business travellers on hotel Wi-Fi, prompting guests to install fake software updates after they logged in with their room number. Kaspersky concluded that public and semi-public hotel Wi-Fi is not safe, so don't let your Mac answer other devices there. ([source](https://www.kaspersky.com/blog/the-dark-story-of-darkhotel/15022/))

**Check it yourself:** `/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate --getstealthmode`

**How to fix:** needs your admin password. Open the Terminal app (Applications → Utilities) and type these, one at a time, pressing Return after each:

1. `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on`. macOS asks for your password; nothing appears on screen while you type it, which is normal.
2. `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on`
3. `sudo -k`, which ends the admin session.

Or click: System Settings → Network → Firewall → on, then Options → Enable stealth mode.

**What the agent is doing:** The agent never runs `sudo` itself. You run admin commands, so you always see exactly what gets admin rights.
