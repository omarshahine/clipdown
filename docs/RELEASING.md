# Releasing ClipDown

ClipDown ships as a signed, notarized app through GitHub Releases, updates itself with Sparkle, and is installable from the public `omarshahine/homebrew-tap`. The pipeline mirrors Spotmoji's.

## Publish a release

1. Confirm the working tree is clean, `main` is pushed, and CI passes.
2. Tag and push: `git tag -a v1.2.3 -m "ClipDown 1.2.3" && git push origin v1.2.3`.
3. Watch the **Release** workflow. It tests, signs with the OmarKnows LLC Developer ID, notarizes and staples, validates the app, publishes the GitHub release with a signed `appcast.xml`, checks that the previous release can upgrade to this one, and updates the Homebrew cask.
4. Check it: `brew update && brew upgrade --cask clipdown` (or `brew install --cask omarshahine/tap/clipdown`), then `spctl --assess --type execute --verbose=2 /Applications/ClipDown.app`.

The app reads its feed from `https://github.com/omarshahine/clipdown/releases/latest/download/appcast.xml`. The cask declares `auto_updates true`, so Homebrew doesn't compete with Sparkle.

## Secrets and variables

| Name | Kind | Purpose |
|---|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | secret | Base64 `.p12` with the Developer ID Application certificate and key |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | secret | Password used when exporting the `.p12` |
| `APP_STORE_CONNECT_API_KEY_ID` | secret | App Store Connect API key ID (notarization) |
| `APP_STORE_CONNECT_API_ISSUER_ID` | secret | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | secret | Contents of the matching `AuthKey_*.p8` |
| `SPARKLE_PRIVATE_KEY` | secret | Base64 Ed25519 seed that signs update archives and the appcast |
| `HOMEBREW_TAP_TOKEN` | secret | Token with contents read/write on `omarshahine/homebrew-tap` |
| `APPLE_TEAM_ID` | variable | Team ID the imported certificate must belong to |

The Sparkle public key is in `scripts/build-app.sh`. Its private half is ClipDown's own (not shared with Spotmoji) and is backed up outside the repo. Losing it means existing installs can't verify new updates, so keep the backup.

Never commit certificates, passwords, keys or tokens.
