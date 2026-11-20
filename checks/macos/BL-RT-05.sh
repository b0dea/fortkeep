#!/bin/bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/apps.sh"
ID=BL-RT-05
# Behavioural protection works only while the product's system extension runs, so an installed app alone isn't enough.
found="$(fortkeep_join "$(fortkeep_endpoint_products)" ', ')"
running="$(fortkeep_endpoint_running)"; rc=$?
running="$(fortkeep_join "$running" ', ')"
if [ -n "$running" ]; then fortkeep_result "$ID" PASS "Endpoint protection running: $running"
elif [ -z "$found" ]; then fortkeep_result "$ID" FAIL "No known endpoint protection or antivirus" "Usually provided by your organisation's IT or security team; if you have none, tell your agent and it records that as your decision"
elif [ "$rc" -ne 0 ]; then fortkeep_result "$ID" ERROR "Endpoint protection installed: $found; could not tell whether it runs" "systemextensionsctl list could not be run or read"
else fortkeep_result "$ID" FAIL "Endpoint protection installed but not running: $found" "Open the app and finish its setup; macOS may be waiting for you to allow its extension in System Settings > General > Login Items & Extensions"; fi
