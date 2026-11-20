---
name: if-red
description: What to do when a scan, alert or the person reports something that looks like real malware or a compromised repo or package. Use for /if-red, an urgent FAIL from /posture or /fix, a HIGH from /scan or the git scan hook, an antivirus alert, or "I think I ran something bad".
metadata:
  internal: "true"
---

# /if-red

The person's steps are in `docs/if-red.md`, written so they work after the Mac is offline and you can't help. Read
it (in Codex: `checks/show.sh docs/if-red.md`) and follow it. Stay calm, short and specific.

1. **Is the Mac affected?** Two findings can stop short of an emergency; for anything else, go on.
   - Only GD-AI-01 (agent control files changed): name the files from its evidence and ask whether the person, or an
     app update, made those changes. If they recognise every one, the "Was it a false alarm?" section of
     `docs/if-red.md` applies.
   - A HIGH from `/scan`: ask whether the person ever installed, built or ran that project, or opened it in an editor
     or agent. If they never did, the Mac shows no harm from it yet: they keep it closed, report it (step 6 of the
     page), and run `/posture` to check the Mac.
   If they don't recognise a change, did any of those things, or aren't sure, go on.
2. **Everything up front.** Step 1 of the page takes the Mac off the network, which ends this conversation. So before
   it, give the person the whole page in a few short lines: go offline, stop using this Mac, rotate from a clean
   device, get help, don't wipe yet, report. Tell them the full page is the file `docs/if-red.md` in the fortkeep
   folder, and that it opens without the internet.
3. **Then step 1:** ask them to turn off Wi-Fi and unplug any network cable now.

Rules:
- Never tell them to rotate credentials, sign in or type passwords on this Mac: always from a clean device.
- On a work Mac, their employer's IT or security team decides; say so.
- Never open, run, decode or upload the suspicious file yourself.
- A flaw in fortkeep itself goes to SECURITY.md (private vulnerability reporting).
