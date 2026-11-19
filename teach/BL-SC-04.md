# BL-SC-04 · Safe Chain age gate pinned at 48 hours or more

**Why:** The age gate is what refuses brand-new, often hijacked, versions. A repo can ship a `.aikido` file that lowers it; a value set in your environment wins over that file.

**Real attack:** Safe Chain's own documentation says the default age gate is 48 hours and that a repo's `.aikido` file can set its own values, which take priority over your home config; so a repo you clone can weaken the gate unless you pin it yourself. ([source](https://github.com/AikidoSec/safe-chain))

**Check it yourself:** `zsh -c 'echo $SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS'` prints 48 or more (the gold standard is 168). Nothing should set `SAFE_CHAIN_MINIMUM_PACKAGE_AGE_EXCLUSIONS`, `SAFE_CHAIN_NPM_CUSTOM_REGISTRIES`, `SAFE_CHAIN_PIP_CUSTOM_REGISTRIES` or `SAFE_CHAIN_MALWARE_LIST_BASE_URL` unless your company asked you to; if it did, tell the agent and it will record that as your decision.

**How to fix:** the BL-SC-02 fix pins it at 168 hours. To install something genuinely new, lower it for that one command in your own Terminal: `SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=0 npm i <pkg>`. Never permanently, and never from an agent.

**What the agent is doing:** reading these settings in four kinds of shell, your interactive one included. It reports only whether they're set and the age in hours.
