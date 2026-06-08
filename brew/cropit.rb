cask "cropit" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/your-username/cropit/releases/download/v#{version}/Cropit-#{version}.tar.gz"
  name "Cropit"
  desc "macOS screenshot and screen recording app"
  homepage "https://github.com/your-username/cropit"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "Cropit.app"

  uninstall quit: "com.ganwar.Cropit"

  zap trash: [
    "~/Library/Preferences/com.ganwar.Cropit.plist",
    "~/Library/Caches/com.ganwar.Cropit",
    "~/Library/Saved Application State/com.ganwar.Cropit.savedState",
  ]

  caveats do
    screen_recording "Cropit needs Screen Recording permission. Grant it in System Settings > Privacy & Security > Screen Recording."
  end
end
