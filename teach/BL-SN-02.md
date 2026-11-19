# BL-SN-02 · nuclei installed for scanning your own services

**Why:** nuclei checks services you expose (a dev server, a home lab, a demo site) for thousands of known misconfigurations and vulnerabilities.

**Real attack:** CISA's directive on exposed management interfaces says admin interfaces are not meant to be reachable from the internet and that attackers have used such devices to get into networks. Orca's honeypot research found secrets exposed on web servers were discovered in under five minutes. ([source](https://www.cisa.gov/news-events/directives/binding-operational-directive-23-02), [source](https://www.helpnetsecurity.com/2023/06/26/cloud-environments-honeypots/))

**Check it yourself:** `nuclei -version` prints a version.

**How to fix:** `brew install nuclei`. Only scan systems you own or are allowed to test.

**What the agent is doing:** checking that the command exists.
