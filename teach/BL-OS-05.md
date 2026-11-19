# BL-OS-05 · Automatic updates on, including security responses

**Why:** Most attacks on Macs use bugs Apple has already fixed. Updates only protect you once they're installed.

**Real attack:** In December 2025 Apple fixed two bugs in WebKit, the engine behind Safari, which it said may have been used in an "extremely sophisticated attack" on specific people; the fixes shipped for Mac in macOS Tahoe 26.2 and Safari 26.2, and the US cyber agency listed both as exploited. ([source](https://www.helpnetsecurity.com/2025/12/15/ios-macos-cve-2025-14174-cve-2025-43529/))

**Check it yourself:** System Settings → General → Software Update → the (i) next to Automatic Updates.

**How to fix:** in that panel, turn on: Check for updates, Download new updates when available, Install Security Responses and system files. Installing macOS updates automatically is recommended too. On macOS 26 (Tahoe), Apple ships urgent fixes between updates as Background Security Improvements, which replaced Rapid Security Responses: in System Settings → Privacy & Security → Background Security Improvements, keep "Automatically Install" on. The check doesn't read that switch yet, so look at it yourself.

**What the agent is doing:** reading four update preferences. "default" in the evidence means you've never changed it, and macOS keeps it on. Settings your organisation manages through a device-management profile aren't read yet.
