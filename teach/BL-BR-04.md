# BL-BR-04 · No crypto wallet extensions on this Mac

**Why:** Wallet extensions are the first thing a stealer goes for. Their vaults sit in the browser profile folder, and one stolen seed phrase empties the wallet for good.

**Real attack:** BeaverTail, malware North Korean attackers hide in fake job-interview coding tests, searches browser profiles for crypto wallet extension folders (MetaMask, Phantom, Binance Wallet, Coinbase Wallet) and sends what it finds back to the attacker. ([source](https://socket.dev/blog/2025-blockchain-and-cryptocurrency-threat-report), [source](https://www.atlassian.com/blog/how-we-build/disrupting-contagious-interview))

**Check it yourself:** look through each browser's extensions page for wallets, and remove any extension you don't use.

**How to fix:** move crypto to a hardware wallet (Ledger, Trezor) or a separate device, then remove the extension. If you hold crypto, keep it off the machine where you run other people's code.

**What the agent is doing:** listing installed extensions by id and name and matching them against known wallets.
