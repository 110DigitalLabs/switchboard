cask "switchboard" do
  version "0.1.1"
  sha256 "47b556ebd07c4ffe81f63679f584aa58ac30d540e0d17e3a9e13176001bd5e44"

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
