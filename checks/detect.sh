#!/bin/bash
# Lists security-relevant tools on this Mac as one JSON object, for /posture setup. Read-only, no network.
. "$(dirname "$0")/lib/common.sh"
. "$(dirname "$0")/lib/apps.sh"
. "$(dirname "$0")/lib/shells.sh"
tf() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }
ep="$(devward_endpoint_products | jq -R . | jq -sc .)"
tls=false
devward_app "Cloudflare WARP" Zscaler "Netskope Client" >/dev/null && tls=true
[ -n "$(devward_shell_probe zsh 'printf "%s" "${NODE_EXTRA_CA_CERTS-}${SSL_CERT_FILE-}"' | tail -n 1)" ] && tls=true
brew=false; vl=false
lp="$(devward_shell_probe zsh-login 'echo "brew $(command -v brew)"; echo "vl $(command -v varlock)"')"
case "$(printf '%s\n' "$lp" | sed -n 's/^brew //p' | tail -n 1)" in /*) brew=true ;; esac
case "$(printf '%s\n' "$lp" | sed -n 's/^vl //p' | tail -n 1)" in /*) vl=true ;; esac
jq -n --argjson brew "$brew" --argjson ep "$ep" --argjson tls "$tls" --argjson vl "$vl" \
  --argjson op "$(tf devward_app 1Password)" --argjson lulu "$(tf devward_app LuLu)" --argjson ls "$(tf devward_app "Little Snitch")" \
  '{homebrew: $brew, varlock: $vl, endpoint: $ep, onepassword: $op, lulu: $lulu, little_snitch: $ls, tls_interception: $tls,
    suggest_overlays: ([if $tls then "tls-proxy" else empty end] + [if ($ep | length) > 0 then "managed-endpoint" else empty end]
      + [if $vl then "secrets-varlock" else empty end])}'
