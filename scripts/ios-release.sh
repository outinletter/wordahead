#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
export DEVELOPER_DIR=/Applications/Xcode-Internal.app/Contents/Developer
test -x "$DEVELOPER_DIR/usr/bin/xcodebuild"
python3 - <<'CHECK_VOLUME'
import plistlib, subprocess
volume=plistlib.loads(subprocess.check_output(['diskutil','info','-plist','/Volumes/XcodeBuild']))
assert volume.get('MountPoint')=='/Volumes/XcodeBuild' and volume.get('FilesystemType')=='apfs', 'XcodeBuild must be mounted APFS'
images=plistlib.loads(subprocess.check_output(['hdiutil','info','-plist']))['images']
assert any(i.get('image-path')=='/Volumes/Data/Xcode/XcodeBuild.sparsebundle' and any(e.get('mount-point')=='/Volumes/XcodeBuild' for e in i.get('system-entities',[])) for i in images), 'Expected existing XcodeBuild sparsebundle is not mounted'
CHECK_VOLUME
build_number="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' ios/WordAhead.xcodeproj/project.pbxproj | head -1)"
archive_path="/Volumes/XcodeBuild/WordAhead-build${build_number}.xcarchive"
app_path="$archive_path/Products/Applications/WordAhead.app"
case "${1:-archive}" in
  preflight)
    xcode-select -p
    printenv DEVELOPER_DIR
    xcrun --find xcodebuild
    xcodebuild -version
    xcrun --sdk iphoneos --show-sdk-path
    xcodebuild -list -project ios/WordAhead.xcodeproj
    xcrun devicectl list devices
    security find-identity -v -p codesigning
    ;;
  archive)
    xcodebuild -project ios/WordAhead.xcodeproj -scheme WordAhead -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /Volumes/XcodeBuild/DerivedData/WordAhead -archivePath "$archive_path" archive
    python3 - "$app_path/Web" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
refs = re.findall(r'<script[^>]+src=["\']([^"\']+)', (root / 'index.html').read_text())
missing = [ref for ref in refs if '://' not in ref and not (root / ref.split('?')[0]).is_file()]
if missing:
    raise SystemExit('Missing bundled scripts: ' + ', '.join(missing))
print('Verified all bundled scripts, including localization module.')
PY
    ;;
  upload)
    options_file="$(mktemp /tmp/wordahead-export.XXXXXX)"
    trap 'rm -f "$options_file"' EXIT
    cat > "$options_file" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>method</key><string>app-store-connect</string><key>destination</key><string>upload</string><key>signingStyle</key><string>automatic</string><key>teamID</key><string>A7QB8PT33N</string><key>manageAppVersionAndBuildNumber</key><false/></dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$archive_path" -exportOptionsPlist "$options_file" -exportPath "/Volumes/XcodeBuild/WordAhead-build${build_number}-export"
    ;;
  install)
    device_id="${2:?Pass the connected iPhone identifier from preflight}"
    xcrun devicectl device install app --device "$device_id" "$app_path"
    ;;
  *) echo 'Usage: ios-release.sh [preflight|archive|upload|install DEVICE_ID]' >&2; exit 2 ;;
esac
