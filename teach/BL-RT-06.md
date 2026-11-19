# BL-RT-06 · tirith terminal guard installed

**Why:** tirith checks what you paste into the terminal and warns about look-alike characters, hidden escape codes and `curl | bash`.

**Real attack:** Unit 42 found fake "I'm not a robot" pages that tell Mac users to open Terminal and paste a command; the command quietly downloads and opens a disk image carrying the AMOS stealer. ([source](https://www.bleepingcomputer.com/news/security/new-macos-clickfix-attack-silently-mounts-dmgs-to-push-infostealer/))

**Check it yourself:** `tirith --version` prints a version.

**How to fix:** install it with Homebrew, following the tirith project's own instructions.

**What the agent is doing:** checking that the command exists.
