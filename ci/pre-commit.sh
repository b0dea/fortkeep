#!/bin/bash
# lefthook pre-commit: refuses commits that would leak local data, secrets or malware markers.
# Exit: 0 clean, 1 refused.
root="$(git rev-parse --show-toplevel)" || exit 1
bad="$(git diff --cached --name-only --diff-filter=ACMR \
  | grep -E '^reports/|^private-paths$|^accepted\.json$|\.pem$|\.key$|(^|/)\.env(\.|$)|(^|/)id_[A-Za-z0-9_]+$' || true)"
if [ -n "$bad" ]; then echo "pre-commit: refusing to commit local or secret files:"; echo "$bad"; exit 1; fi
gitleaks git --pre-commit --staged --redact --no-banner "$root" || exit 1
"$root/ci/marker-scan.sh" --staged || exit 1
