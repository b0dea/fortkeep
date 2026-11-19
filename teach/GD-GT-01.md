# GD-GT-01 · Commits signed with an SSH key

**Why:** A signed commit proves it came from your key. With GitHub's vigilant mode on, anything pushed under your name without your signature is marked "Unverified", so a forged commit stands out.

**Real attack:** PolinRider's spreader amends the last commit, keeps its original author name and date, and force-pushes it, so the history looks untouched. Where the owner signs every commit, the replaced commit shows up unsigned, and that gives it away ([source](https://github.com/OpenSourceMalware/PolinRider), [source](https://github.com/heisdeku/clean-injected-loader)).

**Check it yourself:** `git config --global gpg.format` prints `ssh`, `git config --global commit.gpgsign` prints `true`, and `git log --show-signature -1` shows a good signature.

**How to fix:** give signing a key of its own, protected by a passphrase that the macOS keychain remembers. Type these in the Terminal app:
1. `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_signing -C "$(git config --global user.email)"`, and choose a passphrase.
2. `touch ~/.ssh/config && open -e ~/.ssh/config`, and add at the end:
   ```
   Host *
     UseKeychain yes
     AddKeysToAgent yes
   ```
3. `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_signing`. It asks for the passphrase once; the keychain keeps it.
4. Tell git to sign with it:
   ```
   git config --global gpg.format ssh
   git config --global user.signingkey ~/.ssh/id_ed25519_signing.pub
   git config --global commit.gpgsign true
   git config --global tag.gpgsign true
   ```
5. So `git log --show-signature` can check your signatures in any repo, print the line to add:
   ```
   echo "$(git config --global user.email) namespaces=\"git\" $(cut -d' ' -f1,2 ~/.ssh/id_ed25519_signing.pub)"
   ```
   Open the file with `touch ~/.ssh/allowed_signers && open -e ~/.ssh/allowed_signers`, paste that line, save, then:
   ```
   git config --global gpg.ssh.allowedSignersFile ~/.ssh/allowed_signers
   ```
6. On GitHub, go to Settings → SSH and GPG keys → New SSH key. Choose *Signing key* and paste what `cat ~/.ssh/id_ed25519_signing.pub` prints. On the same page, tick "Flag unsigned commits as unverified" (vigilant mode).

After a restart, if a commit fails with a signing error, run `ssh-add --apple-load-keychain` once. It reloads the key without asking.

**Using 1Password instead:** open your SSH key in 1Password and choose "Configure commit signing", which writes step 4 for you; then do step 6.

**What the agent is doing:** reading three settings from your global git config. The agent never writes your global git config or your SSH files: you type these steps yourself.
