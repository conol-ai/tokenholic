cask "tokenholic" do
  version "0.8.1"
  sha256 "6aaa8a69cbbfb73100c4f7094d99a6723ac96f7dbd137115b9d1dbffaf269e5f"

  url "https://github.com/conol-ai/tokenholic/releases/download/v#{version}/Tokenholic-#{version}.dmg",
      verified: "github.com/conol-ai/tokenholic/"
  name "Tokenholic"
  desc "Menubar app showing what your AI coding subscriptions earn you at API rates"
  homepage "https://tokenholic.app/"

  # Universal build; menubar agent (no Dock icon). macOS 14 Sonoma or newer.
  depends_on macos: :sonoma

  app "Tokenholic.app"

  zap trash: [
    "~/Library/Caches/ai.conol.Tokenholic",
    "~/Library/Caches/Tokenholic",
    "~/Library/HTTPStorages/ai.conol.Tokenholic",
    "~/Library/Preferences/ai.conol.Tokenholic.plist",
    "~/Library/Saved Application State/ai.conol.Tokenholic.savedState",
  ]
end
