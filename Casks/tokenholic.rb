cask "tokenholic" do
  version "0.8.0"
  sha256 "d92848b910ef5a734ded077792fddd1008595259af48beb1846406a92ccc9538"

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
