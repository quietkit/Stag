cask "stag" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/your-username/stag/releases/download/v#{version}/Stag-#{version}.tar.gz"
  name "Stag"
  desc "macOS screenshot and screen recording app"
  homepage "https://github.com/your-username/stag"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Stag.app"

  uninstall quit: "com.ganwar.Stag"

  zap trash: [
    "~/Library/Preferences/com.ganwar.Stag.plist",
    "~/Library/Caches/com.ganwar.Stag",
    "~/Library/Saved Application State/com.ganwar.Stag.savedState",
  ]

  caveats do
    screen_recording "Stag needs Screen Recording permission. Grant it in System Settings > Privacy & Security > Screen Recording."
  end
end
