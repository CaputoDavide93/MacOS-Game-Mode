# DRAFT Homebrew cask for Game Ready. Not submitted, not published, not usable yet.
#
# Do not put this in a tap or submit it until:
#   1. the release zip is signed with a Developer ID, notarised and stapled
#      (docs/notarisation.md), because Homebrew will not accept an unnotarised app;
#   2. the `version` and `sha256` below are the real ones of that release's Game-Ready.zip
#      (TODO(owner): `shasum -a 256 Game-Ready.zip`, or read Game-Ready.zip.sha256);
#   3. `brew audit --cask --new game-ready` and `brew style` pass in a tap checkout.
# Whether homebrew/cask accepts the app (it has a notability bar) is unknown; a personal tap
# (a repository named homebrew-<something>) has no such bar. TODO(owner): choose.
cask "game-ready" do
  version "0.4.0" # TODO(owner): the first notarised release, not 0.4.0
  sha256 "TODO(owner): sha256 of that release's Game-Ready.zip"

  url "https://github.com/CaputoDavide93/MacOS-Game-Mode/releases/download/v#{version}/Game-Ready.zip"
  name "Game Ready"
  desc "Checks Mac, Wi-Fi and internet before cloud gaming and finds what causes lag"
  homepage "https://github.com/CaputoDavide93/MacOS-Game-Mode"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Game Ready.app"

  uninstall quit: "io.github.caputodavide93.gameready"

  # User files only. /var/db/game-ready and the AirDrop-off profile need root and are
  # listed in docs/uninstall.md; a cask cannot honestly remove them.
  zap trash: [
    "~/Library/Application Support/Game Ready",
    "~/Library/Preferences/io.github.caputodavide93.gameready.plist",
  ]
end
