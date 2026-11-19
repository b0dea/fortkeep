# BL-SE-05 · Cloud CLIs use short-lived sessions, not long-lived keys

**Why:** A long-lived cloud key in `~/.aws/credentials` or a service-account JSON file works for anyone who copies it, for months, until someone notices.

**Real attack:** Sysdig documented "LLMjacking": attackers who get hold of cloud credentials use the victim's account to run AI models, which Sysdig estimated could cost the victim over $46,000 a day, and over $100,000 a day with newer models. ([source](https://sysdig.com/blog/growing-dangers-of-llmjacking))

**Check it yourself:** in `~/.aws/credentials`, key ids starting `AKIA` are long-lived; `ASIA` are temporary.

**How to fix:** use `aws sso login` (or another SSO tool) and `gcloud auth login` instead of stored keys. Delete the long-lived keys from the files, then disable them in the cloud console.

**What the agent is doing:** counting key ids by their first four letters and checking the type of Google credential files. It never reads or prints a key.
