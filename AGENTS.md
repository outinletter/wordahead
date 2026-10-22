# Agent instructions

Always minimize token usage.

## iMac Xcode build procedure (all models)

- Before requesting Apple account re-login, diagnose toolchain path, execution permissions, storage mounts, SDK/runtime availability, and signing separately. Never infer expired credentials solely from a failed build or a model change.
- Inspect `xcode-select -p`, `printenv DEVELOPER_DIR`, `xcrun --find xcodebuild`, `xcodebuild -version`, and `xcrun --sdk iphoneos --show-sdk-path`. This Mac currently uses `/Applications/Xcode-Internal.app/Contents/Developer`; `/Applications/Xcode.app` is a symlink. Revalidate paths instead of changing global selection.
- Explicitly use `DEVELOPER_DIR=/Applications/Xcode-Internal.app/Contents/Developer` after validation. Preserve repository scripts, scheme, signing team and export configuration. WordAhead uses team `A7QB8PT33N` and bundle `com.addvalue.wordahead`.
- `Operation not permitted`, cache/FSEvents failures, CoreSimulatorService connection failures, denied Keychain/external-volume access and sandbox `No Accounts` can reflect execution restrictions. If policy permits, retry the same failing operation through the execution tool's approval/escalation mechanism. Never bypass a denial, weaken sandbox settings, use sudo for normal builds, or change credentials.
- Confirm `/Volumes/XcodeBuild` is mounted APFS backed by `/Volumes/Data/Xcode/XcodeBuild.sparsebundle`. Use `-derivedDataPath /Volumes/XcodeBuild/DerivedData/WordAhead`. If disconnected, connect the existing image only with authorization; never silently use internal storage, create another image, or delete one.
- Discover project/workspace and schemes with `xcodebuild -list`. Generic iOS compilation with `CODE_SIGNING_ALLOWED=NO` does not verify signing/distribution. For simulator work use actual listed devices/runtimes; simulators were intentionally removed. Do not download runtimes or recreate devices unless required by the task.
- Retain signing for archive/export. Inspect exact errors and, when necessary, `security find-identity -v -p codesigning` and provisioning availability without exposing credentials. Request re-login only after an explicit account/token failure persists outside sandbox restrictions. Do not auto-add `-allowProvisioningUpdates` or modify certificates/profiles/accounts without authorization.
- Use `scripts/ios-release.sh` for release operations. Save output and report developer path, destination, derived-data path, exit status and concrete error. Distinguish compilation, signing, archive, export and upload success.
- Check all local scripts in archived `Web/index.html` exist before installing/uploading. Successful archive alone does not prove UI behavior. Confirm device installation and installed build number; report whether UI was tested on device or only from archived resources.
- Skip TestFlight tester/group distribution when requested; App Store review still requires uploading a build.
