# OV-TP-02 · Safe Chain scans finish behind TLS inspection

**Why:** Safe Chain checks each install against Aikido's malware feed through a local proxy. Behind TLS inspection, without the company CA, that check times out, and installs either fail or are slowed until someone switches Safe Chain off.

**Real attack:** On 31 March 2026 hijacked axios releases (1.14.1 and 0.30.4) pulled in a dependency whose install script downloaded a remote-access trojan for macOS, Windows or Linux during an ordinary `npm install`. With Safe Chain switched off "for now", nothing checks a release like that before it runs ([source](https://www.microsoft.com/en-us/security/blog/2026/04/01/mitigating-the-axios-npm-supply-chain-compromise/)).

**Check it yourself:** `zsh -c 'npm safe-chain-verify'` finishes and says OK within a few seconds.

**How to fix:** set the CA bundle for non-interactive shells (OV-TP-01), open a new Terminal and try again.

**What the agent is doing:** running Safe Chain's verify command once from a non-interactive shell, with a time limit.
