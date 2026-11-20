load helpers

setup() {
  setup_env
  SC="$HOME/.safe-chain"; mkdir -p "$SC/shims" "$SC/bin"
  for f in shims/npm shims/pip3 bin/safe-chain; do
    printf '#!/bin/bash\necho OK\nexit ${VERIFY_RC:-0}\n' > "$SC/$f"; chmod +x "$SC/$f"
  done
  # The npm shim answers `install` the way $PKG says, and records the folder it ran in.
  cat > "$SC/shims/npm" <<EOF
#!/bin/bash
[ "\$1" = install ] || { echo OK; exit \${VERIFY_RC:-0}; }
pwd > "$BATS_TEST_TMPDIR/install-dir"; printf "%s\n" "\$@" > "$BATS_TEST_TMPDIR/install-args"; ls > "$BATS_TEST_TMPDIR/install-files"
case "\${PKG:-refused}" in
  refused) echo "Exiting without installing malicious packages."; exit 1 ;;
  installed) mkdir -p node_modules/safe-chain-test; exit 0 ;;
  installed-exit-1) mkdir -p node_modules/safe-chain-test; echo "Exiting without installing malicious packages."; exit 1 ;;
  offline) echo "npm error code ENOTFOUND" >&2; exit 1 ;;
  hang) sleep 20 ;;
esac
EOF
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
}
chk() { run /bin/bash "$REPO/checks/macos/$1.sh"; }
shims_first() { printf 'export PATH="$HOME/.safe-chain/shims:$PATH"\n' | tee "$HOME/.zshenv" > "$HOME/.zlogin"; }

@test "BL-SC-01 installed and verify OK → PASS" {
  chk BL-SC-01; [ "$(field status)" = PASS ]
}
@test "BL-SC-01 shims missing → FAIL naming them" {
  rm "$SC/shims/pip3"
  chk BL-SC-01; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *shims/pip3* ]]
}
@test "BL-SC-01 verify fails → FAIL; verify hangs → ERROR" {
  VERIFY_RC=1 chk BL-SC-01; [ "$(field status)" = FAIL ]
  printf '#!/bin/bash\nsleep 20\n' > "$SC/shims/npm"
  FORTKEEP_VERIFY_TIMEOUT=1 chk BL-SC-01; [ "$(field status)" = ERROR ]
}
@test "BL-SC-01 tries the test package in an empty folder of its own, with its install scripts off, and removes it afterwards" {
  chk BL-SC-01; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"test package was refused"* ]]
  [ "$(cat "$BATS_TEST_TMPDIR/install-args")" = "$(printf '%s\n' install --no-save --ignore-scripts safe-chain-test)" ]
  [[ "$(cat "$BATS_TEST_TMPDIR/install-dir")" == "$TMPDIR"/* ]]; [ "$(cat "$BATS_TEST_TMPDIR/install-files")" = package.json ]
  [ -z "$(ls -A "$TMPDIR")" ]
}
@test "BL-SC-01 the test package gets through → FAIL, even when npm then exits with an error" {
  PKG=installed chk BL-SC-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Safe Chain did not refuse the test package" ]
  PKG=installed-exit-1 chk BL-SC-01; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "Safe Chain did not refuse the test package" ]
  [ -z "$(ls -A "$TMPDIR")" ]
}
@test "BL-SC-01 the test package fails without Safe Chain's refusal, or hangs → ERROR" {
  PKG=offline chk BL-SC-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"without Safe Chain's refusal"* ]]
  PKG=hang FORTKEEP_TEST_PACKAGE_TIMEOUT=1 chk BL-SC-01; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"did not finish in 1s"* ]]
  [ -z "$(ls -A "$TMPDIR")" ]
}
@test "BL-SC-02 shims first in every zsh type → PASS" {
  shims_first
  chk BL-SC-02; [ "$(field status)" = PASS ]; [ "$(field evidence)" = "4 of 4 shell types find all 2 Safe Chain commands at the shims" ]
}
@test "BL-SC-02 no start-up files → FAIL" {
  chk BL-SC-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "0 of 4"* ]]
}
@test "BL-SC-02 bash in use but its login file doesn't load the shims → FAIL naming bash -lc" {
  shims_first; touch "$HOME/.bashrc"
  chk BL-SC-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "5 of 6"* ]]; [[ "$(field note)" == *"bash -lc"* ]]
}
@test "BL-SC-02 a later PATH line in ~/.zshrc puts real pip, pip3 and python3 ahead in interactive zsh → FAIL naming them" {
  for n in pip python3; do printf '#!/bin/sh\n' > "$SC/shims/$n"; chmod +x "$SC/shims/$n"; done
  mkdir -p "$HOME/py/libexec/bin"
  for n in pip pip3 python3; do printf '#!/bin/sh\n' > "$HOME/py/libexec/bin/$n"; chmod +x "$HOME/py/libexec/bin/$n"; done
  shims_first; echo 'export PATH="$HOME/py/libexec/bin:$PATH"' > "$HOME/.zshrc"
  chk BL-SC-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == "3 of 4 shell types find all 4 Safe Chain commands"* ]]
  [ "$(field note)" = "Not first in: interactive zsh (pip, pip3, python3 from ~/py/libexec/bin)" ]
}
@test "BL-SC-02 an interactive zsh answers without a TERM, and start-up output isn't read as an answer" {
  shims_first; printf '[ -n "$TERM" ] || exit 0\necho /usr/local/bin/npm\necho W:\n' > "$HOME/.zshrc"
  run env -u TERM /bin/bash "$REPO/checks/macos/BL-SC-02.sh"; [ "$(field status)" = PASS ]
}
@test "BL-SC-02 a shell that ends before answering → ERROR naming it, never PASS" {
  shims_first; echo 'exit 0' > "$HOME/.zshrc"
  chk BL-SC-02; [ "$(field status)" = ERROR ]; [ "$(field note)" = "No answer from: interactive zsh (a start-up file may end the shell early)" ]
}
@test "BL-SC-02 shells that hang → ERROR" {
  echo 'sleep 5' > "$HOME/.zshenv"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SC-02; [ "$(field status)" = ERROR ]
}
apps() {  # fake ps: each argument is "NAME|PATH" for one app launched by launchd; PATH "-" shows no environment
  : > "$BATS_TEST_TMPDIR/apps"; n=100
  for a in "$@"; do n=$((n + 1)); printf '%s|%s\n' "$n" "$a" >> "$BATS_TEST_TMPDIR/apps"; done
  stub ps '
A="$BATS_TEST_TMPDIR/apps"; me="$(id -u)"
case "$1" in
  -axo) [ -f "$BATS_TEST_TMPDIR/psfail" ] && exit 1
        printf "%s 1 0 /usr/libexec/x\n" 99
        while IFS="|" read -r pid name p; do printf "%s 1 %s /Applications/%s.app/Contents/MacOS/%s\n" "$pid" "$me" "$name" "$name"; done < "$A" ;;
  -Eww) pid="$5"; while IFS="|" read -r id name p; do [ "$id" = "$pid" ] || continue
          if [ "$p" = - ]; then echo "/Applications/$name.app/Contents/MacOS/$name"
          else echo "/Applications/$name.app/Contents/MacOS/$name HOME=/x FORTKEEP_FAKE_SECRET=not-a-real-value-0000 PATH=$p TMPDIR=/t"; fi; done < "$A" ;;
esac'
}
userconf() {  # PATH_VALUE MTIME — launchd's stored user config; boot time is fixed at 1700000000
  C="$FORTKEEP_SYSROOT/private/var/db/com.apple.xpc.launchd/config"; mkdir -p "$C"; rm -f "$C/user.plist"
  plutil -create xml1 "$C/user.plist"; plutil -insert PathEnvironmentVariable -string "$1" "$C/user.plist"
  touch -t "$2" "$C/user.plist"
  stub sysctl 'echo "{ sec = 1700000000, usec = 0 } Tue Nov 14 22:13:20 2023"'
}
@test "BL-SC-03 the setting active and every app that shows its PATH has the shims → PASS" {
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  apps "Code|$SC/shims:$SC/bin:/usr/bin:/bin" "Notes|-"
  chk BL-SC-03; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"1 of 1 running apps"* ]]
}
@test "BL-SC-03 an app with launchd's default PATH → FAIL naming it; an app with its own PATH doesn't count" {
  apps "Visual Studio Code|/usr/bin:/bin:/usr/sbin:/sbin" "Tool|/opt/x/bin:/usr/bin" "Cursor|$SC/shims:/usr/bin"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"doesn't start with"* ]]
  [[ "$(field note)" == *"Visual Studio Code"* ]]; [[ "$(field note)" != *Tool* ]]; [[ "$(field note)" == *"admin command"* ]]
}
@test "BL-SC-03 more than five apps without the shims: five are named, the rest counted" {
  D=/usr/bin:/bin:/usr/sbin:/sbin
  apps "A1|$D" "A2|$D" "A3|$D" "A4|$D" "A5|$D" "A6|$D" "A7|$D" "A1|$D"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"doesn't start with"* ]]
  [[ "$(field note)" == "Without the shims: A1, A2, A3, A4, A5 and 2 more. "* ]]
}
@test "BL-SC-03 reports only which apps, never another environment value or any PATH" {
  apps "Code|/usr/bin:/bin:/usr/sbin:/sbin" "Tool|/opt/x/bin:/usr/bin" "Cursor|$SC/shims:/usr/bin"
  chk BL-SC-03; [ "$(field status)" = FAIL ]
  [[ "$output" != *not-a-real-value* ]]; [[ "$output" != *FORTKEEP_FAKE_SECRET* ]]; [[ "$output" != */opt/x/bin* ]]
  [[ "$output" != *TMPDIR* ]]; [[ "$output" != *"$SC"* ]]
  userconf "$SC/shims:/usr/bin:/bin" 202301010000; apps "Cursor|$SC/shims:/usr/bin" "Bar|/usr/bin:/bin:/usr/sbin:/sbin"
  chk BL-SC-03; [ "$(field status)" = PASS ]; [[ "$output" != *not-a-real-value* ]]; [[ "$output" != *"$SC"* ]]
}
@test "BL-SC-03 no app shows its PATH: the stored user PATH decides, and a restart is needed after setting it" {
  apps "Notes|-"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"doesn't start with"* ]]
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  chk BL-SC-03; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"before the last restart"* ]]
  userconf "$SC/shims:/usr/bin:/bin" 202501010000
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *Restart* ]]
  userconf "/usr/bin:/bin" 202301010000
  chk BL-SC-03; [ "$(field status)" = FAIL ]
}
@test "BL-SC-03 an unreadable user config and no app to look at → ERROR with evidence" {
  apps "Notes|-"
  userconf "$SC/shims:/usr/bin" 202301010000; chmod 000 "$C/user.plist"
  chk BL-SC-03; chmod 644 "$C/user.plist"
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-03 a launchd config folder that can't be searched and no app → ERROR with evidence" {
  apps "Notes|-"
  C="$FORTKEEP_SYSROOT/private/var/db/com.apple.xpc.launchd/config"; mkdir -p "$C"; chmod 000 "$C"
  chk BL-SC-03; chmod 755 "$C"
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-03 a user config that converts to something unparsable and no app → ERROR with evidence" {
  apps "Notes|-"
  userconf "$SC/shims:/usr/bin" 202301010000
  stub plutil 'case "$1" in -convert) echo "not json" ;; *) exec /usr/bin/plutil "$@" ;; esac'
  chk BL-SC-03; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-03 an unreadable boot time leaves the stored PATH undecided → ERROR, whatever the apps show" {
  apps "Notes|-"
  userconf "$SC/shims:/usr/bin" 202301010000; stub sysctl 'echo garbage'
  chk BL-SC-03; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *restart* ]]
  apps "Code|/usr/bin:/bin:/usr/sbin:/sbin"
  chk BL-SC-03; [ "$(field status)" = ERROR ]
}
@test "BL-SC-03 running apps that can't be listed are named, never taken as none" {
  apps "Code|$SC/shims:/usr/bin"; touch "$BATS_TEST_TMPDIR/psfail"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"couldn't be listed"* ]]
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  chk BL-SC-03; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *"couldn't be listed"* ]]
}
@test "BL-SC-04 gate pinned at 48+ in every zsh type → PASS" {
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *168* ]]
}
@test "BL-SC-04 gate not set → FAIL saying the default doesn't count" {
  chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"not set"* ]]; [[ "$(field note)" == *"default doesn't count"* ]]
}
@test "BL-SC-04 gate too low → FAIL" {
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=24' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"24 h"* ]]
}
@test "BL-SC-04 exclusions or a custom registry weaken the gate → FAIL" {
  printf 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168\nexport SAFE_CHAIN_NPM_CUSTOM_REGISTRIES=https://r.example\n' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *weaken* ]]
  [[ "$output" != *r.example* ]]
}
@test "BL-SC-04 exclusions alone weaken the gate → FAIL" {
  printf 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168\nexport SAFE_CHAIN_MINIMUM_PACKAGE_AGE_EXCLUSIONS=left-pad\n' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *weaken* ]]
}
@test "BL-SC-04 noisy start-up file still reads the gate → PASS" {
  printf 'echo hello\nexport SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168\n' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = PASS ]
}
@test "BL-SC-04 a gate lowered in ~/.zshrc → FAIL naming interactive zsh" {
  echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=168' > "$HOME/.zshenv"; echo 'export SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=0' > "$HOME/.zshrc"
  chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"interactive zsh (0 h)"* ]]
}
@test "BL-SC-04 shell that hangs → ERROR with evidence" {
  echo 'sleep 5' > "$HOME/.zshenv"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SC-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-04 broken shell (exit 3 in start-up file) → ERROR, not FAIL" {
  echo 'exit 3' > "$HOME/.zshenv"
  chk BL-SC-04; [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
chk_clean() { run env PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash "$REPO/checks/macos/$1.sh"; }

@test "BL-SC-05 neither pnpm nor bun → NA" {
  chk_clean BL-SC-05; [ "$(field status)" = NA ]
}
@test "BL-SC-05 pnpm with default settings → PASS" {
  stub pnpm 'exit 0'
  chk_clean BL-SC-05; [ "$(field status)" = PASS ]
}
@test "BL-SC-05 pnpm allowing all builds globally → FAIL naming the file" {
  stub pnpm 'exit 0'
  mkdir -p "$HOME/Library/Preferences/pnpm"; echo 'dangerously-allow-all-builds=true' > "$HOME/Library/Preferences/pnpm/rc"
  chk_clean BL-SC-05; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Library/Preferences/pnpm/rc"* ]]
}
@test "BL-SC-05 unreadable ~/.npmrc → ERROR" {
  stub pnpm 'exit 0'
  echo 'dangerously-allow-all-builds=false' > "$HOME/.npmrc"; chmod 000 "$HOME/.npmrc"
  chk_clean BL-SC-05; chmod 600 "$HOME/.npmrc"; [ "$(field status)" = ERROR ]
}
@test "BL-SC-05 dangerously-allow-all-builds in ~/.npmrc → FAIL naming .npmrc" {
  stub pnpm 'exit 0'
  echo 'dangerously-allow-all-builds=true' > "$HOME/.npmrc"
  chk_clean BL-SC-05; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *".npmrc"* ]]
}
@test "BL-SC-05 bun only → PASS, names bun, does not claim bun blocks scripts" {
  stub bun 'exit 0'
  chk_clean BL-SC-05; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *bun* ]]
  [[ "$(field evidence)" != *block* ]]
}
@test "BL-SC-05 pnpm 9 runs install scripts by default → FAIL naming 9.15.0" {
  mkdir -p "$BATS_TEST_TMPDIR/pn/bin"
  printf '{"name":"pnpm","version":"9.15.0"}\n' > "$BATS_TEST_TMPDIR/pn/package.json"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/pn/bin/pnpm"; chmod +x "$BATS_TEST_TMPDIR/pn/bin/pnpm"
  ln -s "$BATS_TEST_TMPDIR/pn/bin/pnpm" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-05; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *9.15.0* ]]
}
@test "BL-SC-05 pnpm 10.4.1 → PASS" {
  mkdir -p "$BATS_TEST_TMPDIR/pn/bin"
  printf '{"name":"pnpm","version":"10.4.1"}\n' > "$BATS_TEST_TMPDIR/pn/package.json"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/pn/bin/pnpm"; chmod +x "$BATS_TEST_TMPDIR/pn/bin/pnpm"
  ln -s "$BATS_TEST_TMPDIR/pn/bin/pnpm" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-05; [ "$(field status)" = PASS ]
}
@test "BL-SC-06 none installed → NA" {
  chk_clean BL-SC-06; [ "$(field status)" = NA ]
}
@test "BL-SC-06 pnpm from corepack → PASS" {
  mkdir -p "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js"
  chmod +x "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js"
  ln -s "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-06; [ "$(field status)" = PASS ]
}
@test "BL-SC-06 corepack pnpm plus plain yarn → FAIL naming yarn" {
  mkdir -p "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js"
  chmod +x "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js"
  ln -s "$BATS_TEST_TMPDIR/lib/node_modules/corepack/dist/pnpm.js" "$BATS_TEST_TMPDIR/bin/pnpm"
  stub yarn 'exit 0'
  chk_clean BL-SC-06; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *yarn* ]]
}
@test "BL-SC-06 pnpm symlink into a Homebrew Cellar → FAIL" {
  mkdir -p "$BATS_TEST_TMPDIR/Cellar/pnpm/9/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/Cellar/pnpm/9/bin/pnpm"; chmod +x "$BATS_TEST_TMPDIR/Cellar/pnpm/9/bin/pnpm"
  ln -s "$BATS_TEST_TMPDIR/Cellar/pnpm/9/bin/pnpm" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-06; [ "$(field status)" = FAIL ]
}
@test "BL-SC-06 dangling pnpm symlink → ERROR" {
  ln -s "$BATS_TEST_TMPDIR/nowhere/pnpm" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-06; [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *pnpm* ]]
}
@test "BL-SC-02 a FAIL also names the shell types that timed out" {
  echo 'sleep 5' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SC-02; [ "$(field status)" = FAIL ]
  [[ "$(field note)" == *"Not first in: zsh -c"* ]]; [[ "$(field note)" == *"Timed out: zsh -lc"* ]]
}
@test "BL-SC-04 a FAIL also names the shells that timed out" {
  echo 'sleep 5' > "$HOME/.zlogin"
  FORTKEEP_SHELL_TIMEOUT=1 chk BL-SC-04; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Timed out or failed to start: zsh -lc"* ]]
}
@test "BL-SC-05 a FAIL also names the files it couldn't read" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  stub pnpm 'exit 0'
  echo 'x=1' > "$HOME/.npmrc"; chmod 000 "$HOME/.npmrc"
  mkdir -p "$HOME/Library/Preferences/pnpm"; echo 'dangerously-allow-all-builds=true' > "$HOME/Library/Preferences/pnpm/rc"
  chk_clean BL-SC-05; chmod 600 "$HOME/.npmrc"
  [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not read: ~/.npmrc"* ]]
}
@test "BL-SC-06 a FAIL also names what couldn't be resolved" {
  stub yarn 'exit 0'
  ln -s "$BATS_TEST_TMPDIR/nowhere/pnpm" "$BATS_TEST_TMPDIR/bin/pnpm"
  chk_clean BL-SC-06; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Could not resolve: pnpm"* ]]
}
@test "BL-SC-03 a parent of the launchd config folder that can't be searched and no app → ERROR with evidence" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  apps "Notes|-"
  L="$FORTKEEP_SYSROOT/private/var/db/com.apple.xpc.launchd"; mkdir -p "$L/config"; chmod 000 "$L"
  chk BL-SC-03; chmod 755 "$L"
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-03 the setting active, some apps without the shims → PASS naming them as likely login items" {
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  apps "Cursor|$SC/shims:/usr/bin" "SwiftBar|/usr/bin:/bin:/usr/sbin:/sbin"
  chk BL-SC-03; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *"1 of 2 running apps"* ]]
  [[ "$(field note)" == "Without the shims: SwiftBar. These are usually login items"* ]]; [[ "$(field note)" == *"Dock or Finder"* ]]
}
@test "BL-SC-03 the setting active but no app has the shims → FAIL: the setting isn't taking effect" {
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  apps "SwiftBar|/usr/bin:/bin:/usr/sbin:/sbin" "Notes|-"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"isn't taking effect"* ]]; [[ "$(field note)" == *SwiftBar* ]]
}
@test "BL-SC-03 a setting made after the last restart → FAIL, even when an app has the shims" {
  userconf "$SC/shims:/usr/bin:/bin" 202501010000
  apps "Cursor|$SC/shims:/usr/bin"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "Restart the Mac to apply it."* ]]
}
@test "BL-SC-03 pending and unset: the note names the apps without the shims but doesn't promise a reopen fixes it" {
  apps "SwiftBar|/usr/bin:/bin:/usr/sbin:/sbin"
  userconf "$SC/shims:/usr/bin:/bin" 202501010000
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Without the shims: SwiftBar."* ]]; [[ "$(field note)" != *reopen* ]]
  rm -f "$C/user.plist"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"Without the shims: SwiftBar."* ]]; [[ "$(field note)" != *reopen* ]]
}
@test "BL-SC-03 the setting active: the login-item sentence is kept" {
  apps "SwiftBar|/usr/bin:/bin:/usr/sbin:/sbin" "Cursor|$SC/shims:/usr/bin"
  userconf "$SC/shims:/usr/bin:/bin" 202301010000
  chk BL-SC-03; [[ "$(field note)" == *"reopen it from the Dock or Finder"* ]]
}
@test "BL-SC-03 an unreadable user config and an app without the shims → ERROR with evidence" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  apps "SwiftBar|/usr/bin:/bin:/usr/sbin:/sbin"
  userconf "$SC/shims:/usr/bin" 202301010000; chmod 000 "$C/user.plist"
  chk BL-SC-03; chmod 644 "$C/user.plist"
  [ "$(field status)" = ERROR ]; [ -n "$(field evidence)" ]
}
@test "BL-SC-03 no setting → FAIL, even when every app has the shims" {
  apps "Cursor|$SC/shims:/usr/bin"
  chk BL-SC-03; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"doesn't start with"* ]]
}
