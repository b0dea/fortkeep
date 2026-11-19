# BL-SE-02 · Every SSH key file has a passphrase

**Why:** A key file without a passphrase works for whoever copies it. With a passphrase, a stolen copy is useless on its own.

**Real attack:** In May 2026 poisoned versions of the node-ipc npm package, live for about two hours, harvested the files in `~/.ssh` (private keys, config, known hosts) along with cloud tokens and `.env` files. A key without a passphrase is usable by whoever copies it. ([source](https://semgrep.dev/blog/2026/not-your-ipc-but-node-ipc-npm-hit-again-with-supply-chain-attack-but-this-time-its-not-a-worm))

**Check it yourself:** `ssh-keygen -y -P '' -f ~/.ssh/<key>` should fail with "incorrect passphrase". If it prints a public key, the file has no passphrase.

**How to fix:** add one with `ssh-keygen -p -f ~/.ssh/<key>` (it asks for a new passphrase), or better, move the key into a protected SSH agent such as 1Password's or Bitwarden's (BL-SE-01) and delete the file.

**What the agent is doing:** trying each key file with an empty passphrase. Nothing is printed, and no key leaves its file.
