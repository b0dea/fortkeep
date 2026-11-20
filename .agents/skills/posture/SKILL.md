---
name: posture
description: Review this Mac's security posture against fortkeep's baseline (baseline, gold and optional overlays), explain the results and offer fixes. Use when the person types /posture, asks to check, review or audit their Mac, or opens this repo for the first time.
metadata:
  internal: "true"
---

# /posture

## 1. Set up (first run, or when the person wants to change settings)

Find out whether `reports/config.json` exists by reading it with the read tool (in Codex,
`checks/show.sh reports/config.json`); don't list the folder. If it exists and the person hasn't asked to change their
settings, skip steps 1–4 and go to "New overlays" below.

1. Run `checks/detect.sh` and list the overlays: `checks/overlays.sh list`.
   Say in one sentence which security tools it found.
2. Ask in one question (see "Asking the person" in AGENTS.md):
   - "Do you want to learn as we go?" → `Yes, teach me` / `No, just the results`
   - Only if overlays exist: "Which set-ups or opt-in tools apply to this Mac?" (multiSelect, one option per overlay).
     Label each option with the overlay's `overlay.title` from `controls/controls.json` and describe it as "Pick this
     if " plus its `overlay.pick_if`; never show the bare name. For each overlay named in `suggest_overlays`, end
     that option's description with "(this Mac looks like it uses this)". Never pre-select one; the person decides.
   - "Is there a folder on this Mac that must stay private, even from this review?" → `No` / `Yes, I'll tell you which`
3. `checks/configure.sh --overlays "<comma-separated, or empty>" --teach yes|no`. This records every overlay as
   offered, so none is asked about again.
4. For each private folder the person names: run `checks/ask.sh private add "<path>"` and ask exactly the question it
   prints (in Codex, the person types `Add private folder <path>` or `Don't add` as their whole message). On
   `Add private folder`, run `checks/private.sh add "<path>"` straight away, with the same folder, and say only
   "Added. It will be skipped." If the question script refuses the folder (`/`, the home folder, a folder above it, or
   fortkeep's own folder), the person adds it themselves, if at all, by typing `fortkeep private add "<path>"` in the
   Terminal app. Taking a folder off the list is theirs too: `fortkeep private remove "<path>"`, in the Terminal app.

### New overlays (a config already exists)

1. Run `checks/overlays.sh new`. If it prints nothing, go to the review. If it fails (exits non-zero), say the
   set-up list couldn't be read, and go to the review.
2. Each line it prints is one overlay this Mac hasn't been offered yet, such as
   `{"overlay":"tls-proxy","suggested":true}`. Show each by its `overlay.title` and "Pick this if " plus its
   `overlay.pick_if`, from `controls/controls.json`, never by the bare name. Ask in one question (see "Asking the
   person" in AGENTS.md):
   - Two or more lines: "New set-ups or opt-in tools are available. Which apply to this Mac?" (multiSelect, one option per
     overlay).
   - One line: "Does this new set-up or opt-in tool apply to this Mac: <title>?" → `Yes` / `No`, with the "Pick this
     if" line as the `Yes` option's description.
   - End the description of each `suggested` one with "(this Mac looks like it uses this)". Never pre-select one;
     the person decides.
3. `checks/configure.sh --offered "<every overlay you just asked about>" --add-overlays "<the ones chosen, or empty>"`.
   Every overlay asked about is recorded, so a "no" is remembered and never asked again. Teach mode and earlier
   choices are kept.

## 2. Review

1. If the session started with a WARNING about local changes, repeat it. Before the run, tell the person, briefly:
   - it reads settings and files and changes nothing. It can take several minutes and prints its progress. It uses the
     network only for a few tests, such as one DNS lookup that shows whether DNS filtering works and Safe Chain's
     own test install (`docs/what-fortkeep-touches.md` lists them);
   - macOS may ask whether fortkeep's checks may open the Desktop, Documents or Downloads folder: two checks look
     there for key files and cloned repos. Allowing it is fine; declining makes those checks ERROR;
   - a security tool on the Mac may stop a check; that check then says "Something outside fortkeep stopped this
     check". It is not a failure of the Mac: `/fix` helps them ask for an exclusion for that one check.
   Then `checks/run.sh`, read `reports/latest/results.json` and run `checks/diff.sh`.
2. **Urgent first.** Look up each FAIL's control in `controls/controls.json`. With an urgent FAIL (AGENTS.md, "How
   results work"), show the score, then follow that rule; the review stops there.
3. Show the results in the shape "Showing results" in AGENTS.md sets: the score, the table, the line for the rest.
   Name the layer (baseline, gold or an overlay's title) in a row's "Why" only when it helps.
4. Under the table, one line per change `checks/diff.sh` shows since the last run, as `BL-OS-01 ✗ FAIL → ✓ PASS`.
   Leave this out when nothing changed.
5. If `reports/config.json` has `"teach": true`: for each FAIL, a lesson of two or three lines from `teach/<ID>.md`
   in your own words, led by its ID in bold.
6. What next, as one question. Options: `Fix them one at a time` (`/fix`; only when there is a FAIL or ERROR),
   `Make a summary to share` (`/summary`), `Scan a repo before opening it` (`/scan`), and `Change my settings`
   (repeats the set-up in section 1, for example to add a private folder). Run the skill the person picks.
