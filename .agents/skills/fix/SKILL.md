---
name: fix
description: Work through failed controls from the last /posture run one at a time, with the person's explicit approval for every change. Use when the person types /fix, asks to fix a failed check, or asks to undo a fix.
metadata:
  internal: "true"
---

# /fix

## Before the first fix

Results go stale: the person may have changed something, or restarted the Mac for a fix. Run `checks/run.sh` first,
then read `reports/latest/results.json`. Look up each result in `controls/controls.json`.

1. **Urgent first.** An urgent FAIL (AGENTS.md, "How results work") goes to `/if-red`: offer no fix and no accept,
   for it or anything else.
2. Then take the rest in this order: MUST, then SHOULD, then NICE; within a level, FAIL before ERROR (ACCEPTED and
   NA need nothing). Among FAILs of one level, risk low before medium before high. One control at a time.

## ERROR: the check couldn't decide

There is nothing to fix yet. In a sentence or two, explain what stopped the check, from its evidence and note. Then
ask whether to check it again: `checks/run.sh --only <ID>`. If the evidence says "Something outside fortkeep stopped
this check", a security tool on the Mac killed it: the person asks whoever manages that tool for an exclusion and
never turns the tool off. Offer no fix for an ERROR. If the re-run gives a FAIL, handle it as a FAIL below.

## a) Script fix (`fix` is a path)

1. In two or three sentences, explain what will change, using the teach file's "How to fix". In teach mode, add its
   "What the agent is doing" line.
2. Show the command, `fixes/macos/<ID>.sh apply`, and its undo, `fixes/macos/<ID>.sh undo`.
3. Ask (see "Asking the person" in AGENTS.md) the question `checks/ask.sh <ID> apply` prints, unchanged: its options are
   `Apply <ID>`, `Skip`, `Stop fixing`. The answer `Apply <ID>` is what authorises the change; nothing else does, and
   the hooks record it only for exactly that question.
4. Only if the answer is `Apply <ID>`, run `fixes/macos/<ID>.sh apply`, straight away.
   - Claude Code then shows its own prompt to run the command. Tell the person that before they answer: it is
     expected, they should allow it once, and never choose "always allow" (or "don't ask again") for a fix script.
   - The approval lasts five minutes. If the fix says the approval expired, say so plainly ("the yes you gave timed
     out before the change ran, so nothing changed"), and ask again.
   - Exit 4 (REFUSED): read the message. A missing or expired approval: ask again; never work around it. "not
     exactly a signed release": this copy has local changes; stop fixing and tell the person to reinstall a signed
     release. A mode named in the message (bypass, auto, accept-edits): ask them to switch back to the default mode
     (shift+tab), then ask again.
   - Exit 3 (MANUAL): walk the person through the printed steps. Exit 3 can follow partial changes: those are
     logged in `reports/change-log.md` and can be undone.
   - "nothing to change": it was already fixed; re-run the check and move on.
5. `checks/run.sh --only <ID>` and report the new status.

## b) Admin fix (`fix_needs_admin` is true)

You never run `sudo`. Give the exact commands from the teach file, one numbered step at a time, and tell the person
to open the Terminal app (Applications → Utilities → Terminal), type each one there and press Return. Not in this
chat: a command run from this chat can't ask for a password. Tell them before the first one: macOS asks for their
password (or Touch ID), and nothing appears on screen while they type the password; that is normal, so type it and
press Return. The teach file's last step is "sudo -k", which ends the admin session; keep it. When they say "done", re-run the check.

If the teach file says a restart is needed, tell them how to come back afterwards, before they restart: open the
Terminal app, type `fortkeep agent` and the agent they use now (`fortkeep agent claude`, `codex` or `opencode`), then
`/fix` (in Codex, `$fix`). It checks the Mac again first, so it picks up where they left off.

## c) Guided fix (`fix` is null and no admin command)

Give the click-by-click steps from the teach file, one step per message, and wait for "done". Then re-run the check.

## d) The person wants to keep it as it is

Some controls name alternatives (`alternatives` in `controls/controls.json`, and the lesson's "How to fix"). If the
person uses another tool the check doesn't recognise, this is the path: the reason records which tool.

Ask for a one-line reason in the person's own words. Then ask the question `checks/ask.sh <ID> accept "<reason>"`
prints, unchanged: it names that reason. Only on `Accept <ID>`, run `checks/accept.sh <ID> "<reason>"` straight away,
with exactly the same reason. In Codex they type `Accept <ID> <reason>` as their whole message; use exactly the reason
they typed. It will show as ACCEPTED from the next run. Exit 4 means the answer is missing, expired or was for
another reason: ask again. Never offer this for an urgent FAIL.

## Undo

Ask the question `checks/ask.sh <ID> undo` prints, unchanged: options `Undo <ID>` and `Keep it`. Only on `Undo <ID>`,
run `fixes/macos/<ID>.sh undo`, then re-run the check. The same notes apply as for a fix: Claude Code's own prompt
follows (allow it once, never "always"), and the approval lasts five minutes.
- Exit 4 (REFUSED): read the message, as for a fix.
- Exit 5: there is nothing to undo.
- Exit 6 has two meanings; read the message:
  - It says `undo stopped` or "your later edits stopped the undo". The person changed a file after the fix, so undo
    left that file alone and nothing of theirs was lost. Name the file and say the backup is kept. Then stop.
  - It says `undo incomplete`. Tell the person the undo was incomplete and the backup was kept. Point them to
    `reports/change-log.md` and whoever manages this Mac, and stop.

## Rules

- One `Apply <ID>` answer per fix: never batch approvals.
- Run each command exactly as written here, from the repo folder: the guards refuse any other spelling.
- Every applied change is in `reports/change-log.md` with its undo; point the person to it at the end.
