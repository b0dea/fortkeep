# BL-SC-05 · pnpm and bun still block install scripts

**Why:** Install scripts (`preinstall`, `postinstall`) run code the moment a package lands on your disk. pnpm (version 10 and later) and bun refuse them unless you allow a package; npm still runs them.

**Real attack:** The Shai-Hulud worm (2025) ran from a `postinstall` script, searched the machine for npm and GitHub tokens and cloud keys, and used the stolen npm token to publish infected versions of the victim's other packages. pnpm's own docs note that most compromised packages have used `postinstall` scripts. ([source](https://unit42.paloaltonetworks.com/npm-supply-chain-attack/), [source](https://pnpm.io/supply-chain-security))

**Check it yourself:** `pnpm config get dangerously-allow-all-builds` should not print `true`. Don't set npm's `ignore-scripts=true` globally unless you know which native packages (esbuild, sharp, prisma, electron) you'll need to `npm rebuild`.

**How to fix:** delete the `dangerously-allow-all-builds=true` line from the file the agent names. Allow individual packages per project with `pnpm approve-builds`.

**What the agent is doing:** reading pnpm's global settings files for that one line.
