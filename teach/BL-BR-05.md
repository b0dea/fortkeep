# BL-BR-05 · A separate browser profile for development

**Why:** Development means visiting unknown repos, docs and demo sites and installing developer extensions. A separate profile with no personal logins keeps that away from your email, bank and social accounts.

**Real attack:** In December 2024 attackers phished a Chrome extension maker and pushed a poisoned update of the Cyberhaven extension that was built to steal cookies and access tokens from the sites you visit; the same attack hit other extensions. An extension only sees the profile it is installed in. ([source](https://securityaffairs.com/172491/hacking/chrome-browser-extensions-compromise.html))

**Check it yourself:** your browser's profile menu shows at least two profiles, one used only for development.

**How to fix:** create a new profile (Chrome: profile icon → Add; Firefox: `about:profiles`) and use it only for development, without signing in to personal accounts.

**What the agent is doing:** counting browser profiles. It can't tell which one you use for what.
