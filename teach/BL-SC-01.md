# BL-SC-01 · Safe Chain installed, with shims for scripts and agents

**Why:** Most hijacked npm and PyPI versions are pulled within hours. Safe Chain refuses packages on Aikido's malware feed and any version younger than its age gate, so a fresh hijack never reaches you.

**Real attack:** On 8 September 2025 a fake "npm support" email captured a maintainer's login, and popular packages such as chalk and debug were republished with code that swaps cryptocurrency wallet addresses. npm began removing the bad versions that evening and some were still live the next day, so a 48-hour age gate would have kept them out. ([source](https://blog.checkpoint.com/crypto/the-great-npm-heist-september-2025/), [source](https://www.stepsecurity.io/blog/20-popular-npm-packages-compromised-chalk-debug-strip-ansi-color-convert-wrap-ansi))

**Check it yourself:** in Terminal, `npm safe-chain-verify` says OK and `npm install --no-save --ignore-scripts safe-chain-test` is refused. Safe Chain doesn't cover `cargo`, `go install`, `gem`, `brew` or `deno`: treat those as unscanned, use `cargo install --locked` and pin what you install.

**How to fix:** in the Terminal app, one step at a time. Take the version number and the long checksum from the install command in Safe Chain's README (github.com/AikidoSec/safe-chain):
1. `curl -fsSL https://github.com/AikidoSec/safe-chain/releases/download/<version>/install-safe-chain.sh -o install-safe-chain.sh` downloads the installer, with `<version>` replaced by that number.
2. `shasum -a 256 install-safe-chain.sh` prints the file's checksum. It must be exactly the one in the README; if it isn't, stop and delete the file.
3. `sh install-safe-chain.sh` sets up Safe Chain for your Terminal.
4. `sh install-safe-chain.sh --ci` adds the shims that scripts, editors and agents use.

Never pipe the installer straight into a shell.

**What the agent is doing:** looking for Safe Chain's files, running its verify command once, then asking npm for Safe Chain's harmless test package in an empty temporary folder: it passes only if Safe Chain refuses it. The folder is deleted afterwards, so nothing stays installed even if the test package got through.
