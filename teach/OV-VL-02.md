# OV-VL-02 · varlock's telemetry off

**Why:** varlock sends anonymous usage data unless you turn it off. A tool that can read every secret should send nothing anywhere you didn't choose, and the fewer connections it makes, the easier a strange one is to spot.

**Real attack:** On 29 October 2026 a trojanized Claude Code extension collected the Mac's host and user name, environment variable names and Git email, and reported them to the attacker's server with a web request. From a tool that's expected to phone home, one more request is easy to miss ([source](https://cursor.com/blog/claude-code-extension-security-notice)).

**Check it yourself:** `varlock telemetry disable` writes `"telemetryDisabled": true` into `~/.config/varlock/config.json`.

**How to fix:** run `varlock telemetry disable` in Terminal. Then deny varlock's outbound network in your firewall (BL-RT-03): in Little Snitch or LuLu, add a rule that denies any outgoing connection for the varlock program (`/opt/homebrew/Cellar/varlock/<version>/bin/varlock`), and delete any "<your terminal> via varlock" allow rule, because it overrides the deny. varlock's own work (decrypting with Touch ID, reading the Keychain) needs no network. If you use a plugin that fetches secrets from a cloud vault, allow only that vault's address.

**What the agent is doing:** reading that one setting from varlock's config file, nothing else in it. The agent can't see your firewall rules; that part is yours to check.
