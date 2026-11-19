#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/shells.sh"
ID=BL-SN-02
out="$(devward_shell_probe zsh-login 'command -v nuclei; echo devward-done')"; rc=$?
[ "$rc" -eq 0 ] || out=""
case "$out" in *devward-done*) ;; *) devward_result "$ID" ERROR "Could not look for nuclei" "The login shell did not finish (it failed or took too long)"; exit 0 ;; esac
p="$(printf '%s\n' "$out" | grep -v '^devward-done$' | tail -n 1)"
case "$p" in /*) devward_result "$ID" PASS "nuclei is installed" ;; *) devward_result "$ID" FAIL "nuclei is not installed" ;; esac
