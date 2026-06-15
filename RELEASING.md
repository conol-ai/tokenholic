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
