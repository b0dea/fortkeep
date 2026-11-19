load helpers

setup() {
  setup_env
  REAL_GIT="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v git)"
  stub git "[ \"\$1\" = --version ] && { echo \"git version \${FAKE_GIT_VERSION:-2.56.0}\"; exit 0; }; exec '$REAL_GIT' \"\$@\""
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/bin" > "$HOME/.zlogin"
  cp "$REPO/fixes/files/git-scan-new-files" "$BATS_TEST_TMPDIR/"; chmod +x "$BATS_TEST_TMPDIR/git-scan-new-files"
}
chk() { run /bin/bash "$REPO/checks/macos/$1.sh"; }
hooks() { for e in post-checkout post-merge post-rewrite; do git config --global "hook.s-$e.event" "$e"; git config --global "hook.s-$e.command" "$1 $e"; done; }

@test "git checks never run Apple's /usr/bin/git stub without the Command Line Tools: NA saying they're needed" {
  mkdir -p "$BATS_TEST_TMPDIR/gl"; printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/gl/gitleaks"; chmod +x "$BATS_TEST_TMPDIR/gl/gitleaks"
  printf 'export PATH="%s:/usr/bin:/bin:/usr/sbin:/sbin"\n' "$BATS_TEST_TMPDIR/gl" > "$HOME/.zlogin"   # git is /usr/bin/git
  stub xcode-select 'exit 2'
  for c in BL-RC-02 BL-RC-03 BL-SE-06 GD-GT-01; do
    chk "$c"; [ "$(field status)" = NA ]; [[ "$(field evidence)" == *"needs Apple's Command Line Tools"* ]]
  done
}
@test "BL-RC-02 no hooks → FAIL naming all three events" {
  chk BL-RC-02; [ "$(field status)" = FAIL ]
  [[ "$(field evidence)" == *post-checkout*post-merge*post-rewrite* ]]
}
@test "BL-RC-02 config hooks with a runnable command on git 2.54+ → PASS" {
  hooks "$BATS_TEST_TMPDIR/git-scan-new-files"
  chk BL-RC-02; [ "$(field status)" = PASS ]; [[ "$(field evidence)" == *2.56.0* ]]
}
@test "BL-RC-02 an installed scanner that differs from this repo's → FAIL out of date, naming it" {
  hooks "$BATS_TEST_TMPDIR/git-scan-new-files"
  echo '# older' >> "$BATS_TEST_TMPDIR/git-scan-new-files"
  chk BL-RC-02; [ "$(field status)" = FAIL ]; [ "$(field evidence)" = "The installed scan hook is out of date" ]
  [[ "$(field note)" == "$BATS_TEST_TMPDIR/git-scan-new-files differs from this repo's copy"* ]]
}
@test "BL-RC-02 core.hooksPath hooks with an outdated ~/.local/bin scanner → FAIL out of date" {
  mkdir -p "$HOME/hooks" "$HOME/.local/bin"
  for e in post-checkout post-merge post-rewrite; do printf '#!/bin/sh\nexec "$HOME/.local/bin/git-scan-new-files" %s "$@"\n' "$e" > "$HOME/hooks/$e"; chmod +x "$HOME/hooks/$e"; done
  git config --global core.hooksPath '~/hooks'
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.local/bin/git-scan-new-files"; chmod +x "$HOME/.local/bin/git-scan-new-files"
  chk BL-RC-02; [ "$(field status)" = FAIL ]; [[ "$(field note)" == "~/.local/bin/git-scan-new-files differs"* ]]
  cp "$REPO/fixes/files/git-scan-new-files" "$HOME/.local/bin/"
  chk BL-RC-02; [ "$(field status)" = PASS ]
}
@test "BL-RC-02 config hooks on an older git → FAIL" {
  hooks "$BATS_TEST_TMPDIR/git-scan-new-files"
  FAKE_GIT_VERSION=2.50.1 chk BL-RC-02; [ "$(field status)" = FAIL ]; [[ "$(field evidence)" == *"older than 2.54"* ]]
}
@test "BL-RC-02 a hook whose command can't run → FAIL" {
  hooks "$BATS_TEST_TMPDIR/missing-scan"
  chk BL-RC-02; [ "$(field status)" = FAIL ]
}
@test "BL-RC-02 core.hooksPath with all three hooks → PASS on any git version" {
  mkdir -p "$HOME/hooks"
  for e in post-checkout post-merge post-rewrite; do printf '#!/bin/sh\nexec "$HOME/.local/bin/git-scan-new-files" %s "$@"\n' "$e" > "$HOME/hooks/$e"; chmod +x "$HOME/hooks/$e"; done
  git config --global core.hooksPath '~/hooks'
  FAKE_GIT_VERSION=2.39.0 chk BL-RC-02; [ "$(field status)" = PASS ]
}
@test "BL-RC-02 a hook that runs some other program doesn't count; the scanner by name does, quoted or with ~" {
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/other"; chmod +x "$BATS_TEST_TMPDIR/other"
  hooks "$BATS_TEST_TMPDIR/other"
  chk BL-RC-02; [ "$(field status)" = FAIL ]
  mkdir -p "$HOME/.local/bin"; cp "$BATS_TEST_TMPDIR/git-scan-new-files" "$HOME/.local/bin/"
  hooks '"~/.local/bin/git-scan-new-files"'
  chk BL-RC-02; [ "$(field status)" = PASS ]
}
@test "BL-RC-02 a core.hooksPath hook that can't be read → ERROR with evidence" {
  [ "$(id -u)" -ne 0 ] || skip "root reads everything"
  mkdir -p "$HOME/hooks"; for e in post-checkout post-merge post-rewrite; do printf '#!/bin/sh\nexec git-scan-new-files\n' > "$HOME/hooks/$e"; chmod 111 "$HOME/hooks/$e"; done
  git config --global core.hooksPath '~/hooks'
  chk BL-RC-02; chmod 755 "$HOME/hooks"/*
  [ "$(field status)" = ERROR ]; [[ "$(field evidence)" == *post-checkout* ]]
}
@test "BL-RC-02 a core.hooksPath hook that doesn't call the scanner doesn't count" {
  mkdir -p "$HOME/hooks"; for e in post-checkout post-merge post-rewrite; do printf '#!/bin/sh\nexit 0\n' > "$HOME/hooks/$e"; chmod +x "$HOME/hooks/$e"; done
  git config --global core.hooksPath '~/hooks'
  chk BL-RC-02; [ "$(field status)" = FAIL ]
}
@test "BL-RC-03 push.default simple and no aliases → PASS" {
  git config --global push.default simple
  chk BL-RC-03; [ "$(field status)" = PASS ]
}
@test "BL-RC-03 push.default not set → FAIL saying git's default doesn't count" {
  chk BL-RC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *"not set"* ]]; [[ "$(field note)" == *"default doesn't count"* ]]
}
@test "BL-RC-03 a git alias or a shell alias that force-pushes → FAIL naming it" {
  git config --global push.default simple
  git config --global alias.pf 'push --force'
  echo "alias gpf='git push --force-with-lease'" > "$HOME/.zshrc"
  chk BL-RC-03; [ "$(field status)" = FAIL ]; [[ "$(field note)" == *pf* ]]; [[ "$(field note)" == *gpf* ]]
  [[ "$output" != *--force* ]]
}
@test "BL-RC-02 and BL-RC-03 with a malformed global git config → ERROR" {
  printf '[broken\n' > "$HOME/.gitconfig"
  chk BL-RC-02; [ "$(field status)" = ERROR ]
  chk BL-RC-03; [ "$(field status)" = ERROR ]
}
@test "BL-RC-03 an interactive shell that hangs → ERROR, not zero aliases" {
  git config --global push.default simple
  echo 'sleep 5' > "$HOME/.zshrc"
  DEVWARD_SHELL_TIMEOUT=1 chk BL-RC-03; [ "$(field status)" = ERROR ]
}
@test "BL-RC-02 a login shell that exits non-zero → ERROR" {
  printf 'exit 3\n' >> "$HOME/.zlogin"
  chk BL-RC-02; [ "$(field status)" = ERROR ]
}
