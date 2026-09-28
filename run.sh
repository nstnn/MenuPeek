#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
derived_data="$project_dir/build/DerivedData"
app_path="$derived_data/Build/Products/Debug/MenuPocket.app"

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    echo "Xcode's command-line build tools are unavailable." >&2
    echo "Install Xcode, then select it with:" >&2
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

echo "Building MenuPocket…"
# Avoid the SDK stat-cache step, which stalled with Xcode 16 on this Mac.
/usr/bin/xcodebuild \
    -quiet \
    -project "$project_dir/MenuPocket.xcodeproj" \
    -scheme MenuPocket \
    -configuration Debug \
    -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "$derived_data" \
    SDK_STAT_CACHE_ENABLE=NO \
    build

# Quit only this checkout's app, and wait before launching the rebuilt version.
/usr/bin/osascript -l JavaScript - "$app_path" <<'JXA'
ObjC.import('AppKit');
function run(argv) {
    const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
    for (let i = 0; i < apps.count; i++) {
        const app = apps.objectAtIndex(i);
        if (app.bundleURL.isNil() || ObjC.unwrap(app.bundleURL.path) !== argv[0]) continue;
        if (!app.terminate) throw new Error('Please quit MenuPocket, then run this command again.');
        for (let attempt = 0; attempt < 100 && !app.isTerminated; attempt++) {
            $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
        }
        if (!app.isTerminated) throw new Error('MenuPocket has not quit yet. Quit it and try again.');
    }
}
JXA

/usr/bin/open "$app_path"
echo "MenuPocket launched. Click the grid icon in the macOS menu bar to open the Today task window."
