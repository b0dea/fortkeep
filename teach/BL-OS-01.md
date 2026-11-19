# BL-OS-01 · FileVault on

**Why:** FileVault encrypts the whole disk. If the Mac is lost or stolen, nobody can read your files without your password.

**Real attack:** In 2011 the UK data regulator fined Ealing and Hounslow councils £80,000 and £70,000 after two laptops were stolen from an employee's home; they had passwords but weren't encrypted. The regulator said password protection "is simply not enough". ([source](https://www.itpro.com/630847/london-councils-fined-150000-for-unencrypted-laptop-thefts))

**Check it yourself:** run `fdesetup isactive` in Terminal. It prints `true` when FileVault is on.

**How to fix:** System Settings → Privacy & Security → FileVault → Turn On. Store the recovery key in your password manager, not in a file on this Mac. Encryption finishes in the background; keep working.

**What the agent is doing:** reading a single on/off status. It can't turn FileVault on for you: that click is yours, by design.
