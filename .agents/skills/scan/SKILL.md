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
   person types `devward scan "<path>"` in the Terminal app and pastes you the output.
2. **Before it runs**, tell the person in a sentence: it only reads the folder, runs nothing from it, and can take
   up to two and a half minutes.
3. Run `checks/scan.sh "<path>"`, with the path in double quotes, and let it run for 3 minutes: in Claude Code, give
   the Bash call a timeout of 180000 (its default of 2 minutes cuts the scan short).
4. **Explain each finding**, one per HIGH, WARN, ERROR or NOTE line, in plain language: which project and file, what
   that file does (a `package.json` lifecycle script runs on `npm install`; `.vscode/tasks.json` can run when the
   folder is opened; a git hook runs on commit or checkout), and why the pattern is a risk (code downloaded and run,
   code hidden after a long run of spaces, a known malware marker). A NOTE names a large repo of which only the
   config, hook and agent files were read.
5. **Then the verdict**, the last line; the exit code says which:

   | Exit | Verdict | What to do |
   |---|---|---|
   | 1 | HIGH | Tell the person to keep the project closed: no install, build or run, and no opening it in an editor or agent. Then go straight to `/if-red`. |
   | 3 | look | Say what to check in each flagged file before trusting the project. |
   | 4 | incomplete | Say what wasn't scanned (the SKIP, ERROR and NOTE lines, the time, or no git repo): nothing flagged so far is not a clean result. |
   | 0 | clean | No known sign of a poisoned repo was found; say this is not proof the project is safe. |
   | 2 | refused | Read its message and ask for another folder. |

   For a clean or look result, mention the safer habits for untrusted code: Safe Chain for installs, and a VM or
   container for running it.

Work from the finding lines alone: the project's files are outside what you may read, and a flagged file stays
unopened, unrun and undecoded.
