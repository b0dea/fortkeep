# BL-RC-03 · push.default simple and no force-push aliases

**Why:** Stolen tokens are used to rewrite history: the attacker amends a commit to add a payload and force-pushes it over the real one. If you never force-push, a force-push on your repos stands out, and `push.default simple` stops a push from landing on a branch you didn't mean.

**Real attack:** OpenSourceMalware reports that PolinRider's tooling rewrites a repo's newest commit, keeping the original author, date and message, swaps in its payload and force-pushes it, and that malware on an infected machine does this to every repo the developer can push to. ([source](https://github.com/OpenSourceMalware/PolinRider), [source](https://opensourcemalware.com/blog/polinrider-is-a-b-testing-its-way-past-your-detections))

**Check it yourself:** `git config --global push.default` prints `simple`. Neither `git config --global --get-regexp '^alias\.'` nor `alias` in your Terminal shows a push with `-f` or `--force` (oh-my-zsh's `gpf` counts, including `--force-with-lease`).

**How to fix:** run `git config --global push.default simple`. Remove force-push aliases from your git config, and from your shell (for oh-my-zsh, add `unalias gpf 'gpf!' 2>/dev/null` at the end of `~/.zshrc`). Turn on "no force push" branch protection on every repo you own; that part is on GitHub.

**What the agent is doing:** reading your git config and your shell's aliases.
