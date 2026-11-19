# BL-SC-06 · pnpm and yarn come from corepack

**Why:** Each repo pins its pnpm or yarn version in `package.json` (`packageManager`). Corepack runs exactly that version; a global install runs whatever you happened to install.

**Real attack:** pnpm's install protections are settings of the pnpm version you run, such as a delay before new releases can be installed and blocked build scripts, and its docs say most compromised packages have used `postinstall` scripts. Corepack's `packageManager` field is documented to keep installs deterministic, so everyone runs the version the repo chose. ([source](https://pnpm.io/supply-chain-security), [source](https://github.com/nodejs/corepack#readme))

**Check it yourself:** `ls -l "$(command -v pnpm)"` should point into a `corepack` folder.

**How to fix:** remove the global copy (installed with Homebrew: `brew uninstall pnpm`; with npm: `npm uninstall -g pnpm`), then run `corepack enable`.

**What the agent is doing:** following the pnpm and yarn commands to the file they really run.
