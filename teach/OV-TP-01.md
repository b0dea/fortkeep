# OV-TP-01 · CA bundle exported for non-interactive shells

**Why:** A TLS-inspecting proxy re-signs every HTTPS connection with the company's certificate. Tools started outside your interactive Terminal (agents, editors, scripts) fail or, worse, get told to skip verification unless they're given the company CA bundle.

**Real attack:** Setting `NODE_TLS_REJECT_UNAUTHORIZED=0` to get past certificate errors turns off certificate checks for every TLS connection Node makes, so a real attacker's certificate passes too; Node.js's own documentation calls this insecure and strongly discourages it ([source](https://nodejs.org/api/cli.html#node_tls_reject_unauthorizedvalue)).

**Check it yourself:** `zsh -c 'echo $NODE_EXTRA_CA_CERTS $SSL_CERT_FILE $REQUESTS_CA_BUNDLE'` prints the path of a CA bundle three times.

**How to fix:** get the CA bundle from your company's instructions (or export it from Keychain Access), save it somewhere stable, and add one line to `~/.zshenv`: `export NODE_EXTRA_CA_CERTS=<bundle> SSL_CERT_FILE=<bundle> REQUESTS_CA_BUNDLE=<bundle>`. A bundle that combines public roots with the company CA keeps working when the proxy is off. Never turn certificate checks off instead.

**What the agent is doing:** checking in three kinds of shell that these variables point to a readable certificate file.
