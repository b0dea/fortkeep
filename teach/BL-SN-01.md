# BL-SN-01 · Security scanners installed

**Why:** Free scanners find what's already known to be bad: vulnerable dependencies (osv-scanner, pip-audit), leaked secrets in git history (gitleaks), unsigned releases (cosign), unsafe shell and GitHub Actions (shellcheck, actionlint), and vulnerable Homebrew packages (`brew vulns`).

**Real attack:** The 2017 Equifax breach came through Apache Struts flaw CVE-2017-5638, which was patched on 7 March 2017; the Apache Software Foundation said the compromise was due to Equifax's failure to install the updates in time. A dependency scanner such as `osv-scanner` flags known-vulnerable versions like that. ([source](https://news.apache.org/foundation/entry/media-alert-the-apache-software))

**Check it yourself:** `command -v osv-scanner pip-audit gitleaks cosign shellcheck actionlint` lists all six.

**How to fix:** `brew install osv-scanner pip-audit gitleaks cosign shellcheck actionlint`, and keep Homebrew updated (`brew update`) so `brew vulns` is available. Turn on Dependabot or Renovate in every repo you own; that's the GitHub side.

**What the agent is doing:** checking that the commands exist in your login shell. It runs none of them.
