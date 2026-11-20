---
name: scan
description: Scan one repo, or the git repos in one folder, for signs it is poisoned before the person opens, installs, builds or runs it. Read-only. Use for /scan, "is this repo safe?", a take-home test, a project someone sent, or a freshly cloned or downloaded repo.
metadata:
  internal: "true"
---

# /scan

1. **Which folder.** Use the folder the person named. If they named none, or only a project's name, ask for its
   full path: in Finder, they can drag the folder into this chat, or right-click it with Option held and choose
   "Copy … as Pathname". The path must start with `/` or `~/`. Scan one project folder at a time; the script refuses
   `/`, the home folder and the folders above it. A path with letters beyond ASCII can't be passed from here: the
   person types `fortkeep scan "<path>"` in the Terminal app and pastes you the output.
2. **Before it runs**, tell the person in a sentence: it only reads the folder, runs nothing from it, and can take
   up to two and a half minutes.
3. Run `checks/scan.sh "<path>"`, with the path in double quotes, and let it run for 3 minutes: in Claude Code, give
   the Bash call a timeout of 180000 (its default of 2 minutes cuts the scan short).
4. **Verdict first**, one bold line with its symbol and the number of findings, such as
   `✗ HIGH · 2 findings in 1 project`. The verdict is the scan's last line, which matches one row below; read it
   rather than adding anything to the command to print the exit code (the guards refuse that). Its row is what step 6
   does:

   | Exit | Verdict | What to do |
   |---|---|---|
   | 1 | ✗ HIGH | Tell the person to keep the project closed: no install, build or run, and no opening it in an editor or agent. Then go straight to `/if-red`. |
   | 3 | ! look | Say what to check in each flagged file before trusting the project. |
   | 4 | ! incomplete | Say what wasn't scanned (the SKIP, ERROR and NOTE lines, the time, or no git repo): nothing flagged so far is not a clean result. If it says a temporary file couldn't be written, the agent is in a read-only sandbox (Codex's read-only mode): the person restarts it in its default mode. |
   | 0 | ✓ clean | No known sign of a poisoned repo was found; say this is not proof the project is safe. |
   | 2 | refused | Read its message and ask for another folder. |

5. **Then one table of the findings**, a row per HIGH, WARN, ERROR or NOTE line, most serious first (none: no table):

   | Level | Project | File | What it means |
   |---|---|---|---|
   | HIGH | take-home | `postcss.config.mjs` | Code hidden after a long run of spaces; it runs when the dev server starts. |

   "What it means" is one plain line: what that file does (a `package.json` lifecycle script runs on `npm install`;
   `.vscode/tasks.json` can run when the folder is opened; a git hook runs on commit or checkout) and why the pattern
   is a risk (code downloaded and run, code hidden after a long run of spaces, a known malware marker). A NOTE names
   a large repo of which only the config, hook and agent files were read.
6. **What to do**, from the verdict's row above. For a clean or look result, mention the safer habits for untrusted
   code (Safe Chain for installs, a VM or container for running it), then ask what next as one question:
   `Scan another folder` or `Check this Mac` (`/posture`).

Work from the finding lines alone: the project's files are outside what you may read, and a flagged file stays
unopened, unrun and undecoded.
