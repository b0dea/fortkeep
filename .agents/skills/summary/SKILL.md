---
name: summary
description: Build the shareable posture summary (self-reported) from the last /posture run. Use for /summary, or when the person wants their Mac's security status to share or send to someone.
metadata:
  internal: "true"
---

# /summary

The result is a "posture summary (self-reported)". Call it that; never call it an attestation, a certificate or
proof.

1. If `reports/latest/results.json` is missing, run `/posture` first. If its `run` date is more than 7 days old,
   suggest re-running `/posture` first.
2. Ask the name to show on it: run `summary/name.sh`, then ask with options the name it printed and `Other`.
3. `summary/build.sh --name "<name>"`. It prints the path of `posture-summary.md` and writes `posture-summary.html`
   beside it.
4. Show the person its contents, in the order the summary uses: any urgent FAIL first, then MUST, SHOULD, NICE, and
   within each FAIL, ERROR, ACCEPTED, NA, PASS. Explain:
   - it lists control ids, titles, levels and statuses, the reason the person wrote for each ACCEPTED item, the
     devward version and commit, and a fingerprint (SHA-256 hash) of the controls file, with no file names, paths
     or machine details;
   - it is a self-report: anyone with this Mac's account could change it before sending, so it is not
     tamper-evident. The reader is trusting the person, not the file;
   - the reasons are free text: read them before sharing.
5. Ask whether they want it as a private web page they can share.
   - Claude Code with the Artifact tool: publish `posture-summary.html` as it is: title "Posture Summary
     (self-reported)", icon `shield`, description "Self-reported pass/fail summary of a Mac's security checks
     against devward's baseline.". Never edit or redesign the file; the design lives in
     `templates/posture-summary.html`. Tell them it stays private until they share it from the page's Share menu.
   - Codex, OpenCode, or no Artifact tool: there is no page to publish. Give them the full path of
     `posture-summary.html` (in the folder step 3 printed) and tell them to open it in their browser: in
     Finder, go to that folder and double-click the file. They can send the file itself, or `posture-summary.md`.
6. If there is an urgent FAIL, say before they share it that `/if-red` comes first.
