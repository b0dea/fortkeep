# GD-RT-02 · No new network listeners since your baseline

**Why:** A program that listens on your network address (not only on `127.0.0.1`, this Mac itself) accepts connections from other machines. A new one you didn't expect can be a backdoor waiting for its operator.

**Real attack:** In March 2025 a bug in the Vite dev server (CVE-2025-30208) let anyone who could reach it read any file the server could, keys included. Only servers started with `--host` (or the `server.host` setting), listening beyond this Mac, were exposed; on café or office Wi-Fi, that is everyone nearby ([source](https://github.com/vitejs/vite/security/advisories/GHSA-x574-m823-4x7w)).

**Check it yourself:** in the Terminal app, `netstat -anv -p tcp | grep LISTEN` lists every listening socket with its program; ignore lines whose address starts with `127.` or `::1`.

**How to fix:** find out what the new program is. If it's yours (a dev server, AirPlay, Tailscale, a new app), open the Terminal app, `cd` to this repo, and run `checks/baseline.sh accept`: it shows what would become your baseline and asks you to type `accept`. If you don't recognise it, quit it and type `/if-red`. The agent can't accept a baseline for you, on purpose.

**What the agent is doing:** listing which programs listen beyond this Mac and comparing their names with your baseline. Names, not ports, because many programs pick a new port each time: once `node` or `python3` is in your baseline, a new server either one runs doesn't show up here, while a program new to this Mac always does.
