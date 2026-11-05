cask "tiles" do
  version :latest
  sha256 :no_check

  url "https://github.com/vannaenae/tiles/releases/latest/download/Tiles.zip"
  name "Tiles"
  desc "Free, open-source auto-tiling window manager"
  homepage "https://github.com/vannaenae/tiles"

  depends_on macos: ">= :ventura"

  app "Tiles.app"
  binary "#{appdir}/Tiles.app/Contents/Resources/tiles"

  # Not notarized: clear the quarantine flag so it opens without a Gatekeeper prompt.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Tiles.app"]
  end

  uninstall quit: "io.github.vannaenae.tiles"

  zap trash: [
    "~/.config/tiles",
    "~/Library/Application Support/Tiles",
  ]
end
