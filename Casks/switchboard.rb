cask "switchboard" do
  version "0.1.3"
  sha256 "b98841bdf6eaf377b9f2430e88ad0a2e5c3d0e8c71f134ce4cbb5a2428cdf462"

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
