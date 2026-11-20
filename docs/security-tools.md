# When a security tool stops a check

Antivirus and endpoint protection (EDR: CrowdStrike Falcon, Microsoft Defender, SentinelOne, Bitdefender and others)
watch what programs read, not just what they run. A few fortkeep checks read the same places an infostealer reads, so
a security tool may kill them. The check then shows:

> ! ERROR · Something outside fortkeep stopped this check (signal KILL), most likely a security tool running on this
> Mac: Falcon Sensor. …

The Mac is no less safe because of it, and the rest of the review still counts. That one check has no answer until
the security tool lets it run.

## Which checks, and why they look suspicious

Every check only reads, and each lesson's "What the agent is doing" line (`teach/<ID>.md`) says what. These read
places that infostealers also read:

| Check | What it reads | What a security tool may see |
|---|---|---|
| BL-BR-04 | Each browser profile's extension folders, for crypto-wallet extension IDs | A script walking browser profiles for wallets: credential or wallet theft ("Data from Local System") |
| BL-BR-01, BL-BR-02, BL-BR-03 | Each browser profile's settings, its extension list and the count of saved passwords | Reading browser profile and login data |
| BL-SE-02 | The key files in `~/.ssh`, opened with an empty passphrase to see if each has one | Access to private keys |
| BL-SE-03 | Key and secret files (`.pem`, `.key`, `.p12`, `.env`, `credentials`, `id_*`…) up to four folders deep in Desktop, Documents and Downloads, and at the top of your home folder; it opens each `.pem` and `.key` file to see if it holds a private key | A sweep for keys and secrets |
| GD-RT-03 | Running programs' command lines, your network connections, start-up files, scheduled jobs and temporary folders | Process and network discovery |

So far only BL-BR-04 has been seen killed, by CrowdStrike Falcon. Any of these could be on another Mac.

The repo scanner is a separate program: `/scan`, `fortkeep scan` and the weekly repo sweep (GD-RC-01) run it as
`/usr/bin/python3 -I /Users/<you>/.local/share/fortkeep/fixes/files/git-scan-new-files`. It reads each git repo's
files, hooks and history, looking for known malware markers. If a security tool kills it, `/scan` says the scan is
incomplete and GD-RC-01 says "The repo scanner failed (exit 137)". Ask for the same narrow exclusion as below, with
that command line.

## What to ask for: this one check, nothing wider

Ask whoever manages the security tool to **exclude the one check that was stopped, for the one detection that fired,
on your Mac only**. The narrowest form is the check's command line, exactly as fortkeep starts it:

```
/bin/bash -p /Users/<you>/.local/share/fortkeep/checks/macos/<ID>.sh
```

Keep the `-p`. Without it, bash runs a file named by the `BASH_ENV` variable before the check, so anything that can
start that command line could run its own code inside the excluded process. Sometimes the security tool stops a
program the check started (`sqlite3`, `ssh-keygen`, `jq`) rather than the check itself. The detection names the
process it stopped: the exclusion uses that process's file and command line.

Turn these down, even if they are quicker:

- **The whole fortkeep folder**, or your home folder. You can write to `~/.local/share/fortkeep`, and so can
  anything running as you. Excluding the folder would let anything put in it past the security tool.
- **A process-name exclusion for `bash`**, which would cover every shell script on the Mac.
- **Turning off a protection** (behavioural, machine learning) or moving the Mac to a lighter policy.
- **Turning the security tool off** to get the check to run.

If the tool can't exclude anything narrower than a folder, leave the check as `! ERROR`. One check with no answer
is better than a hole in the security tool.

An exclusion for one script still trusts that script to stay as released, and anything running as you can change it.
fortkeep compares its folder with the signed release when an agent session starts and before an update, and warns
about any file that changed. It notices a replaced check only if the change is still there at one of those moments.

## A message to forward

On a work Mac, send this to your IT or security team, with the check's ID and the time of its run filled in:

> fortkeep (https://github.com/b0dea/fortkeep), an open-source security checkup I run on my Mac, had one check stopped
> by our endpoint protection. It's a false positive: the check is a read-only shell script that looks for
> **\<what it reads, from the table above\>** and reports what it finds. It changes nothing and sends nothing.
>
> - Check: `<ID>`, at `/Users/<you>/.local/share/fortkeep/checks/macos/<ID>.sh`
> - Command line: `/bin/bash -p /Users/<you>/.local/share/fortkeep/checks/macos/<ID>.sh`
> - When: `<date and time of the run>`
>
> Could you add an exclusion for that command line only, for the detection that fired, on my Mac only? Please don't
> exclude the whole fortkeep folder: I can write to it, so that would open a gap. The script's source is in the repo
> under `checks/macos/<ID>.sh`.

## On your own Mac

Open the security tool's threat history or quarantine and find the detection for fortkeep's check. If it lets you
allow that one detection or that one file, do that. If it only offers to allow a folder, leave the check as an
error.

## Per tool

**CrowdStrike Falcon.** BL-BR-04 shows up as a detection with tactic "Collection", technique "Data from Local
System" and "Prevention, process killed". An admin adds an **IOA exclusion** for that detection's pattern, scoped to
your Mac's host group, with:

- Image filename: `/bin/bash`
- Command line: `/bin/bash -p /Users/<you>/\.local/share/fortkeep/checks/macos/BL-BR-04\.sh`

An IOA exclusion skips only that pattern for that command line. A sensor visibility or machine-learning exclusion is
far wider and isn't needed.

**Other tools.** Give your admin the detection's name and time, and ask for that tool's narrowest exclusion: one that
matches the command line above, for that detection only, on your Mac only. If you find exact steps for a tool,
please add them here in a pull request.
