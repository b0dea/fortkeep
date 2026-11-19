# OV-ME-01 · Endpoint protection installed (healthy, where its health can be read)

**Why:** When your organisation manages your Mac's endpoint protection (Microsoft Defender, Bitdefender, CrowdStrike Falcon, SentinelOne, ESET, Sophos, …), it's part of their security promise to their customers. It has to be there and working.

**Real attack:** In September 2024 the macOS 15 Sequoia update broke parts of security tools from CrowdStrike, SentinelOne, Microsoft and others, and Apple's fix came three weeks later. Until a fix lands, a Mac can look protected while its protection isn't fully working ([source](https://techcrunch.com/2024/09/19/apples-new-macos-sequoia-update-is-breaking-some-cybersecurity-tools/), [source](https://techcrunch.com/2024/10/07/apple-fixes-bugs-in-macos-sequoia-that-broke-some-cybersecurity-tools)).

**Check it yourself:** open the product's own window or menu-bar icon; it should say you're protected. For Defender, `mdatp health` shows `healthy : true`.

**How to fix:** restart the app; if it still reports a problem, contact your organisation's IT or security team. Don't uninstall or reconfigure it yourself.

**What the agent is doing:** looking for known endpoint-protection and antivirus apps, and for Defender only, reading its health. For other products the agent can only see that the app is installed, so the result says its health can't be read and you check the product's own window. It changes nothing.
