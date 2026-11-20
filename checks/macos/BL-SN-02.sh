#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SN-02
out="$(fortkeep_shell_probe zsh-login 'command -v nuclei; echo fortkeep-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *fortkeep-done*) ;; *) fortkeep_result "$ID" ERROR "Could not look for nuclei" "The login shell did not finish (it failed or took too long)"; exit 0 ;; esac
p="$(printf '%s\n' "$out" | grep -v '^fortkeep-done$' | tail -n 1)"
case "$p" in /*) fortkeep_result "$ID" PASS "nuclei is installed" ;; *) fortkeep_result "$ID" FAIL "nuclei is not installed" ;; esac
