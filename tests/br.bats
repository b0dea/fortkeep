load helpers

setup() { setup_env; AS="$HOME/Library/Application Support"; }
# As run.sh records it, so a check that something outside stops (an EDR) shows why. That is never a pass of the test,
# even one expecting ERROR: the check didn't run.
chk() {
  run /bin/bash -c '. "$1/checks/lib/common.sh"; out="$(devward_timeout 60 /bin/bash "$1/checks/macos/$2.sh")"; devward_check_verdict "$2" $? "$out" 60' _ "$REPO" "$1"
  printf '%s\n' "$output"
  case "$output" in *'"Something outside devward stopped this check'*) return 1 ;; esac
}
chrome() {  # PROFILE PREFS_JSON — a Chrome profile
  P="$AS/Google/Chrome/$1"; mkdir -p "$P"; printf '%s\n' "$2" > "$P/Preferences"
}
ext() {  # PROFILE_DIR ID NAME
  mkdir -p "$1/Extensions/$2/1.0_0"; jq -n --arg n "$3" '{name:$n}' > "$1/Extensions/$2/1.0_0/manifest.json"
}
firefox() {  # PREFS_LINE EXTENSIONS_JSON — one Firefox profile
  F="$AS/Firefox"; mkdir -p "$F/Profiles/x.default"
  printf '[Profile0]\nName=x\nIsRelative=1\nPath=Profiles/x.default\n' > "$F/profiles.ini"
  printf '%s\n' "$1" > "$F/Profiles/x.default/prefs.js"; printf '%s\n' "$2" > "$F/Profiles/x.default/extensions.json"
}

@test "BR checks are NA with no Chrome-family or Firefox profiles" {
  for c in BL-BR-01 BL-BR-02 BL-BR-03 BL-BR-04 BL-BR-05; do chk "$c"; [ "$(field status)" = NA ]; done
}
@test "BL-BR-01 Chrome default (password manager on) → FAIL; turned off → PASS" {
  chrome Default '{}'
  chk BL-BR-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Chrome* ]]
  chrome Default '{"credentials_enable_service":false}'
  chk BL-BR-01; [ "$(field status)" = PASS ]
}
@test "BL-BR-01 manager off but passwords still saved → FAIL with counts only; never-save entries don't count" {
  chrome Default '{"credentials_enable_service":false}'
  logins() { /usr/bin/sqlite3 "$P/$1" "create table logins(origin_url text, username_value text, password_value blob, blacklisted_by_user int);
    insert into logins values $2;"; }
  logins 'Login Data' "('https://a.example','me','pw-SECRET-7',0),('https://b.example','me','pw-SECRET-8',0),('https://c.example','','',1)"
  chk BL-BR-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Chrome (Default): 2"* ]]
  [[ "$output" != *SECRET* ]]; [[ "$output" != *a.example* ]]
  logins 'Login Data For Account' "('https://d.example','me','x',0)"
  chk BL-BR-01; [[ "$(field note)" == *"Chrome (Default): 3"* ]]
  rm "$P/Login Data" "$P/Login Data For Account"; logins 'Login Data' "('https://c.example','','',1)"
  chk BL-BR-01; [ "$(field status)" = PASS ]
  echo 'not a database' > "$P/Login Data"
  chk BL-BR-01; [ "$(field status)" = ERROR ]
  rm -rf "$AS/Google"; firefox 'user_pref("signon.rememberSignons", false);' '{"addons":[]}'
  echo '{"logins":[{"hostname":"https://a.example","encryptedPassword":"x"}]}' > "$F/Profiles/x.default/logins.json"
  chk BL-BR-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Firefox (x.default): 1"* ]]
}
@test "BL-BR-01 Firefox needs signon.rememberSignons false" {
  firefox '' '{"addons":[]}'
  chk BL-BR-01; [ "$(field status)" = FAIL ]
  firefox 'user_pref("signon.rememberSignons", false);' '{"addons":[]}'
  chk BL-BR-01; [ "$(field status)" = PASS ]
}
@test "BL-BR-01 a managed policy turning it off counts" {
  chrome Default '{}'
  M="$DEVWARD_SYSROOT/Library/Managed Preferences"; mkdir -p "$M"
  plutil -create xml1 "$M/com.google.Chrome.plist"; plutil -insert PasswordManagerEnabled -bool false "$M/com.google.Chrome.plist"
  chk BL-BR-01; [ "$(field status)" = PASS ]
}
@test "BL-BR-01 ERROR when Preferences is not valid JSON" {
  chrome Default 'not json'
  chk BL-BR-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-01 ERROR when Preferences is unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  chrome Default '{}'; chmod 000 "$P/Preferences"
  chk BL-BR-01; chmod 600 "$P/Preferences"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-01 ERROR when Firefox prefs.js is unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  firefox '' '{"addons":[]}'; chmod 000 "$AS/Firefox/Profiles/x.default/prefs.js"
  chk BL-BR-01; chmod 600 "$AS/Firefox/Profiles/x.default/prefs.js"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-01 ERROR when a managed policy file cannot be parsed" {
  chrome Default '{}'
  M="$DEVWARD_SYSROOT/Library/Managed Preferences"; mkdir -p "$M"; echo "<plist><dict>" > "$M/com.google.Chrome.plist"
  chk BL-BR-01; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-02 1Password by id or name in every profile → PASS; one profile without → FAIL" {
  chrome Default '{}'; ext "$P" aeblfdkhhhdcdjpifhhbdiojplfjncoa "1Password – Password Manager"
  chk BL-BR-02; [ "$(field status)" = PASS ]
  firefox '' '{"addons":[]}'
  chk BL-BR-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Firefox* ]]
  firefox '' '{"addons":[{"id":"{d634138d-c276-4fc8-924b-40a0ea21d284}","type":"extension","location":"app-profile","defaultLocale":{"name":"1Password"}}]}'
  chk BL-BR-02; [ "$(field status)" = PASS ]
}
@test "BL-BR-02 Bitwarden or iCloud Passwords count too, by id; another extension doesn't" {
  chrome Default '{}'; ext "$P" abcdefghijklmnopabcdefghijklmnop "Some Other Manager"
  chk BL-BR-02; [ "$(field status)" = FAIL ]
  ext "$P" nngceckbapebfimnlniiiahkandclblb "__MSG_extName__"
  chk BL-BR-02; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"password manager"* ]]
  rm -rf "$P/Extensions/nngceckbapebfimnlniiiahkandclblb"; ext "$P" pejdijmoenmkgeppbflobdenhhabjlaj "__MSG_appName__"
  chk BL-BR-02; [ "$(field status)" = PASS ]
  firefox '' '{"addons":[{"id":"{446900e4-71c2-419f-a6a7-df9c091e268b}","type":"extension","location":"app-profile","defaultLocale":{"name":"Bitwarden"}}]}'
  chk BL-BR-02; [ "$(field status)" = PASS ]
}
@test "BL-BR-02 matches by name when the id is unknown" {
  chrome Default '{}'; ext "$P" abcdefghijklmnopabcdefghijklmnop "1Password – Password Manager"
  chk BL-BR-02; [ "$(field status)" = PASS ]
}
@test "BL-BR-02 ERROR when Firefox extensions.json cannot be parsed" {
  firefox '' 'not json'
  chk BL-BR-02; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-02 ERROR when the Extensions folder is unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  chrome Default '{}'; mkdir -p "$P/Extensions"; chmod 000 "$P/Extensions"
  chk BL-BR-02; chmod 700 "$P/Extensions"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-03 uBlock Origin by name → PASS; none → FAIL" {
  chrome Default '{}'
  chk BL-BR-03; [ "$(field status)" = FAIL ]
  ext "$P" abcdefghijklmnopabcdefghijklmnop "uBlock Origin"
  chk BL-BR-03; [ "$(field status)" = PASS ]
}
@test "BL-BR-02 and BL-BR-03 a turned-off extension doesn't count, in Secure Preferences, Preferences or Firefox" {
  chrome Default '{}'; ext "$P" aeblfdkhhhdcdjpifhhbdiojplfjncoa "1Password"; ext "$P" cjpalhdlnbpafiamejdnhcphjbkeiagm "uBlock Origin"
  echo '{"extensions":{"settings":{"aeblfdkhhhdcdjpifhhbdiojplfjncoa":{"disable_reasons":[]},"cjpalhdlnbpafiamejdnhcphjbkeiagm":{"disable_reasons":[1]}}}}' > "$P/Secure Preferences"
  chk BL-BR-02; [ "$(field status)" = PASS ]
  chk BL-BR-03; [ "$(field status)" = FAIL ]
  rm "$P/Secure Preferences"; chrome Default '{"extensions":{"settings":{"aeblfdkhhhdcdjpifhhbdiojplfjncoa":{"disable_reasons":1}}}}'
  chk BL-BR-02; [ "$(field status)" = FAIL ]
  chk BL-BR-03; [ "$(field status)" = PASS ]
  rm -rf "$AS/Google"
  firefox '' '{"addons":[{"id":"uBlock0@raymondhill.net","type":"extension","location":"app-profile","active":false,"userDisabled":true,"defaultLocale":{"name":"uBlock Origin"}}]}'
  chk BL-BR-03; [ "$(field status)" = FAIL ]
}
@test "BR checks cover the Beta, Dev and Canary channels; Brave Beta keeps its shields" {
  C="$AS/Google/Chrome Canary/Default"; mkdir -p "$C"; echo '{}' > "$C/Preferences"
  chk BL-BR-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Chrome Canary (Default)"* ]]
  rm -rf "$AS/Google"; B="$AS/BraveSoftware/Brave-Browser-Beta/Default"; mkdir -p "$B"; echo '{}' > "$B/Preferences"
  chk BL-BR-03; [ "$(field status)" = PASS ]
}
@test "BL-BR-03 the uBlock Origin id alone counts, whatever the name" {
  chrome Default '{}'; ext "$P" cjpalhdlnbpafiamejdnhcphjbkeiagm "Something Else"
  chk BL-BR-03; [ "$(field status)" = PASS ]
}
@test "BL-BR-03 a Brave profile alone counts (shields)" {
  B="$AS/BraveSoftware/Brave-Browser/Default"; mkdir -p "$B"; echo '{}' > "$B/Preferences"
  chk BL-BR-03; [ "$(field status)" = PASS ]
}
@test "BL-BR-03 Brave does not cover a Chrome profile without a blocker" {
  B="$AS/BraveSoftware/Brave-Browser/Default"; mkdir -p "$B"; echo '{}' > "$B/Preferences"
  chrome Default '{}'
  chk BL-BR-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Chrome* ]]; [[ "$(field note)" != *Brave* ]]
}
@test "BL-BR-03 ERROR when Firefox extensions.json cannot be parsed" {
  firefox '' 'not json'
  chk BL-BR-03; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-04 a wallet by id or by name → FAIL naming it; none → PASS with the extension count" {
  chrome Default '{}'; ext "$P" cjpalhdlnbpafiamejdnhcphjbkeiagm "uBlock Origin"
  chk BL-BR-04; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"1 extension"* ]]
  ext "$P" nkbihfbeogaeaoehlefnkodbefgpgknn "MetaMask"
  chk BL-BR-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *MetaMask* ]]
  rm -r "$P/Extensions/nkbihfbeogaeaoehlefnkodbefgpgknn"; ext "$P" aaaabbbbccccddddeeeeffffgggghhhh "Some Crypto Wallet"
  chk BL-BR-04; [ "$(field status)" = FAIL ]
}
@test "BL-BR-04 a wallet matched by id alone (name does not say wallet) → FAIL" {
  chrome Default '{}'; ext "$P" egjidjbpglichdcondbcbdnbeeppgdph "Something Else"
  chk BL-BR-04; [ "$(field status)" = FAIL ]
}
@test "BL-BR-04 ERROR when the Extensions folder is unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  chrome Default '{}'; mkdir -p "$P/Extensions"; chmod 000 "$P/Extensions"
  chk BL-BR-04; chmod 700 "$P/Extensions"; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-04 ERROR when Firefox extensions.json cannot be parsed" {
  firefox '' 'not json'
  chk BL-BR-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-05 two profiles in one browser → PASS; one each → FAIL" {
  chrome Default '{}'
  firefox '' '{"addons":[]}'
  chk BL-BR-05; [ "$(field status)" = FAIL ]
  chrome "Profile 1" '{}'
  chk BL-BR-05; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *Chrome* ]]
}
answers() {  # ADDRESS... — what the system resolver gives for every name; never the real network
  local a out="name: x\n"
  for a in "$@"; do case "$a" in *:*) out="${out}ipv6_address: $a\n" ;; *) out="${out}ip_address: $a\n" ;; esac; done
  stub dscacheutil "printf '$out'"
}
dns() { answers 104.18.4.35; stub scutil "cat <<'EOS'
DNS configuration

resolver #1
  nameserver[0] : $1
  nameserver[1] : ${2:-$1}
  flags    : Request A records

resolver #2
  domain   : local
  options  : mdns

resolver #3
  domain   : corp.example
  nameserver[0] : 10.9.9.9

DNS configuration (for scoped queries)

resolver #1
  nameserver[0] : 8.8.8.8
EOS"; }
@test "BL-BR-06 filtering resolvers → PASS; split-DNS and scoped resolvers are ignored" {
  dns 1.1.1.2 1.0.0.2
  chk BL-BR-06; [ "$(field status)" = PASS ]
}
@test "BL-BR-06 a plain public resolver → FAIL; a router or local resolver → FAIL with the ACCEPTED hint" {
  answers 104.18.4.35 2606:4700::6812:423   # the test name resolves: nothing filters it
  dns 1.1.1.1
  chk BL-BR-06; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *1.1.1.1* ]]
  [[ "$(field note)" == *"resolved malware.testcategory.com"* ]]
  dns 192.168.1.1
  chk BL-BR-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"record that as your decision"* ]]
}
@test "BL-BR-06 any other set-up that blocks the malware test name → PASS, by 0.0.0.0, a block page or no answer" {
  dns 192.168.1.1
  answers 0.0.0.0 ::; chk BL-BR-06; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == "DNS filtering works"* ]]
  answers 146.112.61.106; chk BL-BR-06; [ "$(field status)" = PASS ]
  stub dscacheutil 'case "$*" in *example.com*) printf "name: example.com\nip_address: 93.184.215.14\n" ;; esac'
  chk BL-BR-06; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"returned no address for"* ]]
}
@test "BL-BR-06 no network (no answer even for example.com) → ERROR, not FAIL" {
  dns 100.100.100.100; stub dscacheutil 'exit 0'
  chk BL-BR-06; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"answered nothing"* ]]
}
@test "BL-BR-06 the NextDNS app running → PASS" {
  dns 192.168.1.1; mkdir -p "$DEVWARD_SYSROOT/Applications/NextDNS.app"; stub pgrep '[ "$2" = NextDNS ]'
  chk BL-BR-06; [ "$(field status)" = PASS ]
}
@test "BL-BR-06 ERROR when scutil fails" {
  stub scutil 'exit 1'
  chk BL-BR-06; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-06 ERROR when scutil lists no DNS servers" {
  stub scutil 'echo "DNS configuration"'
  chk BL-BR-06; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-06 ERROR when scutil hangs" {
  stub scutil 'sleep 30'
  DEVWARD_SCUTIL_TIMEOUT=1 chk BL-BR-06; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-BR-04 a wallet in one profile is a FAIL even when another profile can't be read, and the note names it" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  firefox '' '{"addons":[{"id":"webextension@metamask.io","type":"extension","location":"app-profile","defaultLocale":{"name":"MetaMask"}}]}'
  chrome Default '{}'; mkdir -p "$P/Extensions"; chmod 000 "$P/Extensions"
  chk BL-BR-04; chmod 700 "$P/Extensions"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *MetaMask* ]]; [[ "$(field note)" == *"Could not read: Chrome (Default)"* ]]
}
@test "BL-BR-01..03 a profile that fails outranks one that can't be read, and the note names it" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  firefox '' '{"addons":[]}'
  chrome Default '{}'; mkdir -p "$P/Extensions"; chmod 000 "$P/Extensions"
  chk BL-BR-02; o2="$output"; chk BL-BR-03; o3="$output"; chmod 700 "$P/Extensions"
  chmod 000 "$P/Preferences"; chk BL-BR-01; chmod 600 "$P/Preferences"
  for output in "$o2" "$o3" "$output"; do
    [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Firefox* ]]; [[ "$(field note)" == *"Could not read: Chrome (Default)"* ]]
  done
}
@test "BR checks skip a private Chrome-family profile or browser folder and say only that one was excluded" {
  chrome "Profile 3" '{}'; ext "$P" abcdefghijklmnopabcdefghijklmnop "MetaMask"
  printf '%s\n' "$P" > "$DEVWARD_PRIVATE_PATHS"
  for c in BL-BR-01 BL-BR-02 BL-BR-03 BL-BR-04 BL-BR-05; do
    chk "$c"; [ "$(field status)" = NA ]; [[ "$output" == *"a private folder was excluded"* ]]; [[ "$output" != *"Profile 3"* ]]
  done
  chrome Default '{"credentials_enable_service":false}'
  chk BL-BR-01; [ "$(field status)" = PASS ]; [[ "$(field note)" == *"a private folder was excluded"* ]]
  printf '%s\n' "$AS/Google/Chrome" > "$DEVWARD_PRIVATE_PATHS"
  chk BL-BR-01; [ "$(field status)" = NA ]; [[ "$output" == *"a private folder was excluded"* ]]
}
@test "BR checks skip a Firefox profile inside a private folder and say only that one was excluded" {
  F="$AS/Firefox"; X="$HOME/Secret/ff.default"; mkdir -p "$F" "$X"
  printf '[Profile0]\nName=x\nIsRelative=0\nPath=%s\n' "$X" > "$F/profiles.ini"
  printf '\n' > "$X/prefs.js"; echo '{"addons":[]}' > "$X/extensions.json"
  printf '~/Secret\n' > "$DEVWARD_PRIVATE_PATHS"
  for c in BL-BR-01 BL-BR-02 BL-BR-03 BL-BR-04 BL-BR-05; do
    chk "$c"; [ "$(field status)" = NA ]
    [[ "$output" == *"a private folder was excluded"* ]]; [[ "$output" != *Secret* ]]; [[ "$output" != *ff.default* ]]
  done
  chrome Default '{}'
  chk BL-BR-01; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Chrome* ]]
  [[ "$(field note)" == *"a private folder was excluded"* ]]; [[ "$output" != *Secret* ]]
}
