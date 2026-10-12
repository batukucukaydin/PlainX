# Homebrew Cask (draft)

The cask below is ready to publish once a signed release exists. Replace
`<VERSION>` and `<SHA256>` with the `PlainX-Editor-<VERSION>-universal.dmg`
values from the GitHub release, and copy this file to your tap repository at
`Casks/plainx.rb` (or submit to homebrew/homebrew-cask).

```ruby
cask "plainx" do
  version "<VERSION>"
  sha256 "<SHA256>"

  url "https://github.com/your-org/plainx-editor/releases/download/v#{version}/PlainX-Editor-v#{version}-universal.dmg"
  name "PlainX Editor"
  desc "Fast, lightweight native text and code editor"
  homepage "https://github.com/your-org/plainx-editor"

  app "PlainX.app"

  zap trash: [
    "~/Library/Application Support/PlainX",
    "~/Library/Preferences/com.batukucukaydin.plainx.plist",
    "~/Library/Saved Application State/com.batukucukaydin.plainx.savedState",
  ]
end
```

Users then install with:

```bash
brew install --cask plainx
```

Verification before publishing:

```bash
brew audit --cask --new plainx
brew install --cask plainx
brew uninstall --cask --zap plainx
```
