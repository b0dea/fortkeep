#!/bin/bash
# Compiles controls/*.yaml and controls/overlays/*.yaml into one JSON array. Dev/CI only (needs yq).
# An overlay file is a map: its title and pick_if line, then its controls; each of its controls carries both as
# `overlay`, so the set-up question can show them.
set -euo pipefail
cd "$(dirname "$0")/.."
{
  yq -o=json eval-all '. as $item ireduce ([]; . + $item)' controls/baseline.yaml controls/gold.yaml
  for f in controls/overlays/*.yaml; do
    [ -e "$f" ] || continue
    yq -o=json '.' "$f" | jq '. as $o | .controls | map(. + {overlay: {title: $o.title, pick_if: $o.pick_if}})'
  done
} | jq -s 'add' > "${1:-controls/controls.json}"
