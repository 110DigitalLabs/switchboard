cask "switchboard" do
  version "0.1.4"
  sha256 "6b7592fb3e7552493c2c784ab913bb507cb5e5df2662475e22d373fb1d05402e"

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
