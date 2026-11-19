# BL-RT-04 · Microphone and camera monitor installed

**Why:** It tells you when any app turns on your microphone or camera, and which app it was.

**Real attack:** In 2016 researcher Patrick Wardle showed Mac malware that waits for a real video call and records through the same camera stream, so the green camera light gives no warning; a monitor like OverSight alerts when a new process uses the camera or microphone. ([source](https://9to5mac.com/2016/10/06/mac-malware-webcam-microphone/))

**Check it yourself:** turn on your camera in any app and watch for the alert.

**How to fix:** install OverSight (free, objective-see.org) or Micro Snitch (about $5).

**What the agent is doing:** checking that one of them is installed.
