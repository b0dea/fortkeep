# If fortkeep finds signs of malware

Read this whole page first. Step 1 takes your Mac off the internet, and after that your coding agent can't help.
It is written for anyone, and works without fortkeep or an agent. Stay calm: going step by step matters more than
going fast.

## 1. Take the Mac off the network

Turn off Wi-Fi (the Wi-Fi icon in the menu bar, or Control Center) and unplug any network cable. That cuts off
anything that is sending your data out or taking orders from outside.

Leave the Mac switched on, and don't restart it unless the people helping you say so: what is running now can show
what happened.

## 2. Stop using this Mac

Don't type passwords on it, don't sign in to anything, and don't open the suspicious project, file or app again.

## 3. Change your passwords and keys from a clean device

Use your phone or another computer you trust, never this Mac: anything you type here may be read. Do the ones you
actually use, in this order:

1. GitHub and cloud accounts (AWS, Google Cloud, Azure, and so on): revoke your access tokens and keys, then change
   the passwords.
2. SSH keys: remove this Mac's public keys from GitHub and from the servers they open. You'll make new keys later,
   on a clean machine.
3. Sign out everywhere: most services (Google, GitHub, Slack, your email) have a "sign out of all sessions" option.
4. Crypto wallets, if a wallet was ever on this Mac: move the funds to a new wallet created on a clean device.
5. Passwords and keys kept in project files (such as `.env` files): replace each one with the service that issued it.

## 4. Get help

- **A work Mac:** tell your employer's IT or security team now. Say what you ran or opened, and when. They decide
  what happens next; follow them rather than this page.
- **Your own Mac:** contact an incident-response service (a company that investigates break-ins on computers). If
  you can't, at least wait to decide on step 5 until you've rotated everything in step 3.

## 5. Don't wipe it yet

Erasing or reinstalling the Mac destroys the evidence of what was taken and how. Decide that with the people helping
you. Keep the suspicious file or project: don't delete it, don't open it.

## 6. Report it

- The bad package to its registry's security team (npm or PyPI), and the repo or package to
  [OpenSourceMalware](https://opensourcemalware.com), so others are warned.
- A flaw in fortkeep itself (a check that missed something, or a false alarm you can reproduce): see
  [SECURITY.md](../SECURITY.md).

## Was it a false alarm?

One warning has an everyday cause: "agent control files changed since your baseline" also appears when you, or an
app update, changed one of those files (such as `~/.zshrc`). If you recognise every change it lists, it is not an
emergency: open the Terminal app, go to the fortkeep folder and type `checks/baseline.sh accept`. If you don't
recognise a change, treat it as real and start at step 1.
