cask "tokenholic" do
  version "0.8.2"
  sha256 "351be754dbdfb31d8205ce907af8f8821303e2f098b87ac7dc24476073fe3da2"

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
