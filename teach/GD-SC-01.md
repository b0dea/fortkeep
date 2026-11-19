# GD-SC-01 · Safe Chain age gate at 168 hours in every shell type

**Why:** The baseline's 48-hour gate catches most hijacked versions; a week (168 hours) catches the ones that stay up longer, at the cost of waiting a few days for genuinely new releases.

**Real attack:** `fluid-type-ui`, a fake Tailwind plugin carrying a North Korean remote-access trojan, was on npm from 28 July to 3 August 2026, about six days, before npm replaced it. A 48-hour gate would have let it in after two days; a one-week gate refused it the whole time ([source](https://opensourcemalware.com/blog/nullreceiver-dprk-c2-technique), [source](https://registry.npmjs.org/fluid-type-ui)).

**Check it yourself:** `zsh -c 'echo $SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS'` and `bash -lc 'echo $SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS'` both print 168 or more.

**How to fix:** the BL-SC-02 fix pins it at 168 hours in every shell type it sets up. If you set the value yourself somewhere, raise it to 168.

**What the agent is doing:** reading that one setting in each kind of shell.
