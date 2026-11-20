# Roadmap

What's left to build. What fortkeep doesn't stop yet is in the [threat model](threat-model.md#known-limits).

## Next: after 0.1.0

- **Run on more kinds of Mac.** Different macOS versions, managed Macs, other security tools and each agent's newer
  versions. Wrong results reported through the issue forms come first. 1.0 follows once it has.
- **Measure a run.** How long a full check takes on a reference Mac, and which checks are slow.
- **A versioned indicator pack.** Malware indicators that update without a new release, each with its public source,
  and a cross-check against public malicious-package data when a release is built.
- **More agents**, as they gain hooks that can carry the guards.

## Follow-ups

- Pin `jq` for development.

## Later (v2+)

Indicator pack updates (new PolinRider markers and hosts as they appear); plugin packaging; Windows and Linux; a
standalone lessons track; central reporting; a clean-VM test harness.
