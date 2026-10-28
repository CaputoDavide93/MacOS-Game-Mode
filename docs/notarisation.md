# Notarisation checklist

Today the release is ad-hoc signed and not notarised, so the first launch needs **Open Anyway**.
Notarising needs an Apple Developer Program membership and a Developer ID certificate, which
only the owner can get. Nothing here has been run. Do not sign or notarise from an agent.

**Owner prerequisites**

- [ ] TODO(owner): Apple Developer Program membership (paid, yearly).
- [ ] TODO(owner): a "Developer ID Application" certificate in the login keychain.
- [ ] TODO(owner): a notary credential stored once with
      `xcrun notarytool store-credentials "game-ready-notary"` (an app-specific password or an
      API key). Never commit it; CI would need it as a repository secret.

**Build and sign**

- [ ] Hardened runtime is already on (`ENABLE_HARDENED_RUNTIME` in `project.yml`); the only
      entitlement is Apple Events (`App/GameReady.entitlements`). Confirm no more are needed.
- [ ] `SIGN_ID="Developer ID Application: <name> (<team id>)" scripts/build.sh` (the script
      already honours it; see `.env.example`).
- [ ] `codesign --verify --deep --strict --verbose=2 "build/dd/Build/Products/Release/Game Ready.app"`
- [ ] Check the signature is not ad hoc: `codesign -dv --verbose=4 "<app>"` shows a Developer ID
      authority and `flags=…(runtime)`.

**Notarise**

- [ ] Zip for upload: `ditto -c -k --keepParent "<app>" Game-Ready-notarise.zip`
- [ ] `xcrun notarytool submit Game-Ready-notarise.zip --keychain-profile game-ready-notary --wait`
- [ ] If it fails: `xcrun notarytool log <submission id> --keychain-profile game-ready-notary`
- [ ] `xcrun stapler staple "<app>"` then `xcrun stapler validate "<app>"`
- [ ] Re-zip the **stapled** app as `dist/Game-Ready.zip` and recompute `Game-Ready.zip.sha256`.

**Check like a user**

- [ ] On a Mac that has never run it: download the zip in a browser, open the app. Expected: no
      Open Anyway step. `spctl --assess --type execute --verbose "<app>"` says "accepted" with
      source "Notarized Developer ID".
- [ ] Game Mode still asks for the password and works (the privileged path is unchanged, but
      re-run the real-Mac rows in [testing.md](testing.md) on the signed build).

**Then change the docs that say "not notarised"**: README (install step 2, "Build from
source", Supported and tested), `docs/setup.md`, `docs/faq.md`, `docs/troubleshooting.md`,
`llms.txt`, `scripts/build.sh` comment, and `.github/workflows/release.yml` notes. Search for
"notaris" and "Open Anyway". Only edit them once a notarised release actually exists.

**Automate later (optional)**: add signing and `notarytool` to `release.yml` with the
credentials as repository secrets; that makes releases depend on those secrets, so decide
deliberately.

**Homebrew**: with a notarised release, fill the TODO(owner) lines in
[`packaging/homebrew/game-ready.rb`](../packaging/homebrew/game-ready.rb), put it in a tap, and
run `brew audit --cask --new` and `brew style` there. Homebrew is then the update channel
(`brew upgrade --cask`); the app itself still makes no update checks, as [privacy.md](privacy.md) promises.
