# Releasing Tokenholic

Tokenholic ships as a **Developer ID-signed, notarized DMG** built by the
**Build DMG** GitHub Action (`.github/workflows/build-dmg.yml`). It is *not*
distributed via the Mac App Store: Tokenholic reads `~/.claude` and `~/.codex`,
which the App Store sandbox would block. Developer ID + notarization keeps those
reads frictionless.

## Cut a release

```sh
# bump CFBundleShortVersionString in App/Info.plist, then:
git tag v0.1.0
git push origin v0.1.0
```

The tag triggers the workflow, which builds a **universal** (Intel + Apple
Silicon) DMG, signs + notarizes it (when the secrets below are set), and attaches
it to a GitHub Release. You can also run it on demand: Actions → *Build DMG* →
*Run workflow*.

### Homebrew cask

The same tagged run then **auto-bumps the Homebrew cask** (`Casks/tokenholic.rb`):
it recomputes the DMG's `sha256`, updates `version` + `sha256`, and commits the
change back to `main` (`cask: bump Tokenholic to vX.Y.Z [skip ci]`) using the
built-in `GITHUB_TOKEN` — no extra secret. Users install with
`brew tap conol-ai/tokenholic https://github.com/conol-ai/tokenholic` then
`brew install --cask tokenholic`, and update with `brew upgrade --cask tokenholic`.

To regenerate the cask by hand (e.g. for an older tag): `scripts/update-cask.sh [tag]`.

> If `main` is a protected branch requiring PRs, the auto-push step will fail;
> either allow the Actions bot to push, or run `scripts/update-cask.sh` and open
> the bump PR yourself.

## Signing secrets (one-time, needs a paid Apple Developer account)

Add under Settings → Secrets and variables → Actions:

| Secret | What |
|---|---|
| `MACOS_CERTIFICATE` | base64 of your "Developer ID Application" `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `MACOS_CERTIFICATE_PWD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | any throwaway string for the CI keychain |
| `AC_API_KEY` | contents of your App Store Connect `AuthKey_XXXXXXXXXX.p8` |
| `AC_API_KEY_ID` | the key id (the `XXXXXXXXXX` in the `.p8` filename) |
| `AC_API_ISSUER_ID` | the App Store Connect issuer id (a UUID) |

The Developer ID signing identity is **auto-detected** from the imported
certificate — no `MACOS_SIGN_IDENTITY` secret needed.

**Without these secrets the workflow still runs** — it produces an *ad-hoc*-signed
DMG artifact that runs locally but shows a Gatekeeper warning on other Macs.

## Build locally

```sh
make                      # ad-hoc-signed Tokenholic.app
.build/release/Tokenholic --dump        # earnings pipeline + ccusage cross-check
```
