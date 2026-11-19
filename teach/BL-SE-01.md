# BL-SE-01 · SSH keys live in a protected SSH agent (1Password, Secretive or Bitwarden)

**Why:** Stealers copy `~/.ssh` first. With your keys in a protected SSH agent there is no key file to copy, and each use needs your approval (Touch ID or a click).

**Real attack:** OX Security found npm packages, traced to earlier North Korean campaigns, that run a script at install time and go after SSH keys, crypto wallets, browser logins and cloud configuration files on the developer's machine. ([source](https://www.ox.security/blog/north-korean-npm-infostealer-rat))

**Check it yourself:** `ssh -G github.com | grep -i identityagent` (or `echo $SSH_AUTH_SOCK`) shows your agent's socket: 1Password's ends in `2BUA8C4S2C.com.1password/t/agent.sock`, Secretive's in `com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh`, Bitwarden's in `.bitwarden-ssh-agent.sock`.

**How to fix:** pick one, turn on its SSH agent, then add the matching two lines to the top of `~/.ssh/config`:
- **1Password** (paid): Settings → Developer → "Use the SSH agent", and import your keys.

      Host *
        IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

- **Secretive** (free, open source): it makes new keys inside the Mac's Secure Enclave, which can't be exported; add their public keys to GitHub and your servers.

      Host *
        IdentityAgent "~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"

- **Bitwarden** (free): Settings → "Enable SSH agent", and import your keys. From the Mac App Store version, use `~/Library/Containers/com.bitwarden.desktop/Data/.bitwarden-ssh-agent.sock` instead.

      Host *
        IdentityAgent "~/.bitwarden-ssh-agent.sock"

Once SSH works through the agent, delete the key files from `~/.ssh` (keep the `.pub` files if you like). If you use another agent the check doesn't know, tell the agent to record it as your decision (ACCEPTED) with its name as the reason. If you can't use any, at least give every key a passphrase (BL-SE-02).

**What the agent is doing:** checking which of these apps is installed, whether its agent socket exists, and that ssh is set to use it. It never reads a key.
