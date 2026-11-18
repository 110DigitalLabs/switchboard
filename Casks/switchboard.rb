cask "switchboard" do
  version "0.1.0"
  sha256 "b4c6d5e4df6a598b47639792844296d04ce4a46b2cd25473a4733a0b749f63b9"

  url "https://github.com/110DigitalLabs/switchboard/releases/download/v#{version}/Switchboard-#{version}.zip"
  name "Switchboard"
  desc "Session manager for AI coding-agent CLIs"
  homepage "https://github.com/110DigitalLabs/switchboard"

  depends_on macos: :sonoma

  app "Switchboard.app"

  zap trash: [
    "~/Library/Application Support/Switchboard",
    "~/Library/Preferences/dev.switchboard.Switchboard.plist",
    "~/Library/Saved Application State/dev.switchboard.Switchboard.savedState",
  ]
end
