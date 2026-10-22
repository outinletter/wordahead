# Agent instructions

- Always minimize token usage.
- iOS bundle: `com.addvalue.wordahead`; signing team: `A7QB8PT33N` (not a login credential).
- Use `scripts/ios-release.sh` for archive/upload/install. Xcode.app resolves to Xcode-Internal.app on this Mac.
- Xcode signing, Keychain, provisioning profiles, CoreDevice, and `/Volumes/XcodeBuild` require host access. In Codex, run these commands with `sandbox_permissions: require_escalated` when the restricted environment cannot access them. Obtain tool approval using the user's authorized build/install/upload request. Never interpret sandbox `No Accounts`, invalid/missing profiles, or CoreDevice initialization failures as proof the user is logged out; retry with host access first.
- Do not delete accounts, profiles, certificates, change signing teams, or request account login merely because a sandboxed build fails. Never copy credentials into this repository or log them.
- After archive, verify every local script referenced by bundled `Web/index.html` exists in the archive before installing or uploading. A successful archive alone is insufficient.
- Device install must report success; verify installed app version/build. Do not claim language behavior was tested on iPhone unless actually observed.
- App Store upload is separate from TestFlight tester distribution. If the user skips TestFlight, upload for App Store review without adding testers/groups.
