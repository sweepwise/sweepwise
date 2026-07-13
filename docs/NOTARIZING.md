# Notarizing Sweepwise

Notarization lets users open Sweepwise normally instead of the current
right-click → Open dance. macOS Gatekeeper stops warning once the app is
signed with a **Developer ID** certificate, scanned by Apple's notary service,
and has the resulting ticket stapled to it.

Everything in `scripts/notarize.sh` is automated. The parts below are the
one-time account setup only you can do.

## One-time setup

1. **Join the Apple Developer Program** — https://developer.apple.com/programs/
   ($99/year). Ad-hoc signing (the default `bundle.sh` output) can never be
   notarized; you need a real Team ID and certificate.

2. **Create a "Developer ID Application" certificate.**
   Easiest via Xcode: Settings → Accounts → (your Apple ID) → Manage
   Certificates → **+** → *Developer ID Application*. It lands in your login
   keychain. Confirm it's there:

   ```
   security find-identity -v -p codesigning
   ```

   You'll use the full string, e.g. `Developer ID Application: Jane Doe (AB12CD34EF)`.

3. **Store notary credentials once** (an app-specific password from
   https://appleid.apple.com → Sign-In and Security → App-Specific Passwords):

   ```
   xcrun notarytool store-credentials sweepwise-notary \
     --apple-id "you@example.com" \
     --team-id "AB12CD34EF" \
     --password "abcd-efgh-ijkl-mnop"
   ```

## Every release

```
SWEEPWISE_SIGN_IDENTITY="Developer ID Application: Jane Doe (AB12CD34EF)" \
  ./scripts/notarize.sh
```

That builds the universal binary, signs it with a hardened runtime, uploads it
to Apple, waits for the result, staples the ticket, and re-zips
`dist/Sweepwise.zip` ready to attach to a GitHub release.

## Notes

- **No entitlements needed.** Sweepwise loads no plugins and isn't sandboxed;
  the default hardened runtime is enough. Shelling out to the AI CLIs via
  `Process` is allowed under the hardened runtime.
- If notarization is rejected, `xcrun notarytool log <submission-id>
  --keychain-profile sweepwise-notary` prints the exact reason.
- The stapled app works fully offline — the ticket is embedded, so Gatekeeper
  doesn't need to phone home on first launch.
