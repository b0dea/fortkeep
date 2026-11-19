# BL-OS-08 · Touch ID for sudo

**Why:** Typing your admin password into a terminal over and over invites shoulder-surfing and lets anything recording keystrokes capture it. Touch ID proves you're physically there.

**Real attack:** Trend Micro found the AMOS stealer showing a "System Preferences" box that asked for the Mac password and kept reappearing until it was entered, then saved the real password to a hidden file. With Touch ID for sudo you rarely type that password, so an unexpected prompt stands out. ([source](https://www.trendmicro.com/en_us/research/25/i/an-mdr-analysis-of-the-amos-stealer-campaign.html))

**Check it yourself:** `cat /etc/pam.d/sudo_local` shows an uncommented `auth sufficient pam_tid.so` line.

**How to fix:** needs your admin password once. If `/etc/pam.d/sudo_local` doesn't exist yet, open the Terminal app (Applications → Utilities) and type these, one at a time, pressing Return after each:

1. `sudo sh -c 'sed "s/^#auth/auth/" /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local'`. macOS asks for your password; nothing appears on screen while you type it, which is normal.
2. `sudo -k`, which ends the admin session.

If the file already exists, ask the agent: it will show you the one line to add without removing what's there. This file survives macOS updates.

It doesn't apply (NA) when this Mac has no Touch ID sensor (a Mac mini or Mac Studio without a Touch ID keyboard), or when your account isn't an administrator and so can't use sudo at all.

**What the agent is doing:** reading the file, whether your account is an administrator, and whether the Mac has a Touch ID sensor. The agent never runs sudo; you run the command and see exactly what it changes.
