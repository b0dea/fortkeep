#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
ID=BL-OS-08
f="$(devward_path /etc/pam.d/sudo_local)"
if [ -f "$f" ] && grep -Eq '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$f"; then
  devward_result "$ID" PASS "Touch ID for sudo: on"; exit 0
fi
# Only an administrator runs sudo, and only a Touch ID sensor (built in, or a keyboard with one set up) can answer it.
case " $(id -Gn 2>/dev/null) " in *" admin "*) ;; *) devward_result "$ID" NA "This account isn't an administrator, so it can't use sudo"; exit 0 ;; esac
if [ -z "$(ioreg -r -c AppleBiometricSensor -d 1 2>/dev/null)" ] \
  && ! bioutil -c 2>/dev/null | grep -Eq '[1-9][0-9]* biometric template'; then
  devward_result "$ID" NA "This Mac has no Touch ID sensor"; exit 0
fi
devward_result "$ID" FAIL "Touch ID for sudo: off" "Needs admin rights: the agent will give you the command to run"
