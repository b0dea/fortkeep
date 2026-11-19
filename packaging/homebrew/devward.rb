# frozen_string_literal: true

# Homebrew formula for devward. It lives here and is copied to the b0dea/homebrew-tap repository as Formula/devward.rb
# when a release is published; ci/release-pins.sh prints the url, sha256 and COMMIT to paste in.
#
# Why devward itself isn't in the Cellar: devward runs from a git checkout of a signed release tag. Its agent guards
# load from that folder, your settings and results live in it, its integrity check compares the folder with the signed
# tag, and `devward update` moves it between signed tags. A Cellar copy has no git history, and `brew upgrade` would
# swap it under the guards. So this formula installs only a small shim. On first run the shim makes that checkout in
# ~/.local/share/devward with the release's own install.sh, pinned to this release's commit, then hands over to it.
class Devward < Formula
  desc "Security checkup for developer Macs, run with your coding agent"
  homepage "https://github.com/b0dea/devward"
  url "https://github.com/b0dea/devward/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
  license "MIT"

  # The release tag's commit: install.sh refuses a clone whose tag isn't exactly this commit.
  COMMIT = "0000000000000000000000000000000000000000"

  depends_on macos: :sequoia

  def install
    libexec.install "install.sh"
    (bin/"devward").write <<~SH
      #!/bin/bash
      # devward's Homebrew shim: makes the checkout of release v#{version} on first run, then runs devward from it.
      # The installer talks on stderr, so the first `devward version --json` or `check --json` prints only its JSON.
      d="$HOME/.local/share/devward"
      if [ ! -x "$d/bin/devward" ]; then
        /bin/bash "#{libexec}/install.sh" --tag "v#{version}" --commit "#{COMMIT}" --no-link >&2 || exit
      fi
      exec "$d/bin/devward" "$@"
    SH
  end

  def caveats
    <<~EOS
      The first time you run devward, it clones release v#{version} into ~/.local/share/devward and checks its
      signature. Updates come from `devward update`, not `brew upgrade`. Start with: devward agent
    EOS
  end

  test do
    system "/bin/bash", "-n", libexec/"install.sh"
  end
end
