# BL-BR-01 · Browsers' built-in password manager off

**Why:** Chrome-family browsers and Firefox keep saved passwords in files on disk. Stealers know exactly where, and decrypt them after one Keychain prompt or a fake password dialog. A locked password manager vault (1Password, Bitwarden, or Apple's Passwords app, which keeps them in the Keychain) gives them far less.

**Real attack:** Trend Micro analysed an AMOS stealer infection that showed a fake "System Preferences" password box, kept asking until the real Mac password was typed, and copied saved logins from browsers including Chrome, Firefox, Edge, Brave, Opera and Vivaldi. ([source](https://www.trendmicro.com/en_us/research/25/i/an-mdr-analysis-of-the-amos-stealer-campaign.html))

**Check it yourself:** Chrome → Settings → Autofill and passwords → Google Password Manager → Settings → "Offer to save passwords" off. Firefox → Settings → Privacy & Security → "Ask to save passwords" off. Then delete the saved passwords after moving them to your password manager.

**How to fix:** move your saved passwords into your password manager (1Password, Bitwarden and Apple's Passwords app can import them), switch off saving in each browser and profile the agent names, then delete what's still saved there. Turning saving off doesn't delete what's saved: the check fails while any saved password is left in a browser profile, and names how many. Safari isn't checked, and Apple Passwords users pass: those passwords are in the Keychain, not a browser file.

**What the agent is doing:** reading one setting in each browser profile's settings file, and counting the saved passwords in each profile's password file. It counts rows only; it never opens or reads a password.
