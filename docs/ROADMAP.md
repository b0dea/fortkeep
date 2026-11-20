# Roadmap

What's left to build. What fortkeep doesn't stop yet is in the [threat model](threat-model.md#known-limits).

## Next: after 0.1.0

- **Run on more kinds of Mac.** Different macOS versions, managed Macs, other security tools and each agent's newer
  versions. Wrong results reported through the issue forms come first. 1.0 follows once it has.
- **Exact exclusion steps per security tool.** `docs/security-tools.md` has CrowdStrike Falcon's; Defender,
  SentinelOne, Bitdefender and others come from the wrong-result reports of people whose tool stopped a check.
- **Measure a run.** How long a full check takes on a reference Mac, and which checks are slow.
- **A versioned indicator pack.** Malware indicators that update without a new release, each with its public source,
  and a cross-check against public malicious-package data when a release is built.
- **A daily light check.** An optional daily run of only the urgent checks (live malware, poisoned repos), which are
  quick; the full review stays weekly.
- **An agent-led hunt.** An optional scan where your agent looks through this Mac's repos and start-up files for
  PolinRider-like patterns the fixed indicators don't name yet: odd config files, new hooks, long encoded lines. It
  needs a safe way to show the agent those excerpts as data; today the agent reads nothing outside fortkeep's folder.
- **A repo sweep that resumes.** The sweep gets time for the repos there are, up to a limit. On a Mac with more
  repos than that covers, it should carry on where the last sweep stopped, so a few runs cover them all.
- **More agents**, as they gain hooks that can carry the guards.

## Follow-ups

- Pin `jq` for development.

## Later (v2+)

Indicator pack updates (new PolinRider markers and hosts as they appear); plugin packaging; Windows and Linux; a
standalone lessons track; central reporting; a clean-VM test harness.
