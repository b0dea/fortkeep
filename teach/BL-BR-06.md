# BL-BR-06 · DNS filtering with malware blocklists

**Why:** Filtering DNS refuses to look up known malware, phishing and command-and-control domains, so many attacks fail at the first connection.

**Real attack:** The UK's National Cyber Security Centre runs a filtering DNS service that refuses to look up known-malicious domains, because malware on an infected machine normally finds its controller through a DNS lookup, and so does a clicked phishing link; when the lookup is refused, the connection never starts. ([source](https://www.ncsc.gov.uk/pdfs/information/pdns.pdf))

**Check it yourself:** System Settings → Network → your connection → Details → DNS shows 1.1.1.2 and 1.0.0.2 (or Quad9's or NextDNS's servers). For any other set-up, `dscacheutil -q host -a name malware.testcategory.com` in the Terminal app should print no address: that name is Cloudflare's published malware test name.

**How to fix:** set your DNS servers to `1.1.1.2` and `1.0.0.2` (Cloudflare with malware blocking, free) or `9.9.9.9` (Quad9, free), or use NextDNS (paid, with a free tier) with its malware blocklists on.

**What the agent is doing:** reading which DNS servers macOS uses. If they aren't on its list of known filtering services, it makes one DNS lookup of `malware.testcategory.com` and passes if your DNS blocks it; only if that gets no answer at all, it looks up `example.com` to tell a block from no network. `docs/what-fortkeep-touches.md` lists every network use.
