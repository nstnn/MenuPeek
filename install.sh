#!/bin/bash
# Build this checkout's Release app and replace the installed copy recoverably.
set -euo pipefail

open_app=1
case "${1:-}" in
    --no-open) open_app=0; shift ;;
    --help|-h)
        echo "Usage: ./install.sh [--no-open]"
        echo "Build Release, back up saved data, replace /Applications/MenuPocket.app, and launch it."
        echo "The old app goes to Trash. --no-open installs without launching."
        exit 0 ;;
esac
[[ $# == 0 ]] || { echo "Unknown argument. Use --help." >&2; exit 1; }

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
target_app="/Applications/MenuPocket.app"
bundle_id="local.menupocket.app"
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
lock_dir="/Applications/.MenuPocket-install.lock"
staged_app="/Applications/.MenuPocket-install-$$.app"
old_trash=""
installed=0
committed=0
locked=0
staged_owned=0
built_app=""
app_tool=""

fail() { echo "install.sh: $*" >&2; exit 1; }

# FileManager's Trash API is recoverable and does not require UI permissions.
trash_app() {
    local path="$1" trashed
    [[ -e "$path" ]] || return 0
    "$lsregister" -u "$path" >/dev/null 2>&1 || true
    trashed="$("$app_tool" trash "$path")" || return 1
    # Moving an app can register its new Trash path again.
    "$lsregister" -u "$trashed" >/dev/null 2>&1 || true
    echo "$trashed"
}

cleanup() {
    local result=$?
    trap - EXIT
    if [[ $committed == 0 ]]; then
        if [[ $installed == 1 ]]; then
            trash_app "$target_app" >/dev/null || echo "Could not remove the failed new app." >&2
        fi
        if [[ -n "$old_trash" ]]; then
            if [[ ! -e "$target_app" ]] && "$app_tool" move "$old_trash" "$target_app"; then
                "$lsregister" -f "$target_app" >/dev/null 2>&1 || true
                echo "Restored the previous app at $target_app." >&2
            else
                echo "Previous app is recoverable at: $old_trash" >&2
            fi
        fi
    fi
    for path in "$staged_app" "$built_app"; do
        [[ "$path" != "$staged_app" || $staged_owned == 1 ]] || continue
        [[ -n "$path" && -e "$path" ]] || continue
        trash_app "$path" >/dev/null || { echo "Cleanup failed for $path" >&2; result=1; }
    done
    if [[ -n "$old_trash" && -e "$old_trash" ]]; then
        "$lsregister" -u "$old_trash" >/dev/null 2>&1 || true
    fi
    if [[ $locked == 1 ]]; then
        /bin/rmdir "$lock_dir" || result=1
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ ! -L "$target_app" ]] || fail "Installed app is a symlink; leaving it untouched."
[[ -w /Applications ]] || fail "This account cannot write to /Applications."
/usr/bin/xcodebuild -version >/dev/null 2>&1 || fail "Select a working Xcode installation first."
/usr/bin/python3 --version >/dev/null 2>&1 || fail "Python 3 from the Xcode command-line tools is required."
if [[ -e "$target_app" ]]; then
    installed_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist")"
    [[ "$installed_id" == "$bundle_id" ]] || fail "Unexpected app at $target_app; leaving it untouched."
fi
/bin/mkdir "$lock_dir" 2>/dev/null || fail "Another install is active, or $lock_dir remains from an interrupted install."
locked=1

/bin/mkdir -p "$project_dir/build"
run_dir="$(/usr/bin/mktemp -d "$project_dir/build/install-release.XXXXXX")"
built_app="$run_dir/DerivedData/Build/Products/Release/MenuPocket.app"
backup_dir="$run_dir/backup"
app_tool="$run_dir/app-tool"
cat >"$run_dir/AppTool.swift" <<'SWIFT'
import AppKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else { fail("Missing app operation/path.") }
do {
    switch arguments[0] {
    case "trash":
        var destination: NSURL?
        try FileManager.default.trashItem(at: URL(fileURLWithPath: arguments[1]), resultingItemURL: &destination)
        guard let path = destination?.path else { fail("Trash did not report its destination.") }
        print(path)
    case "move":
        guard arguments.count == 3 else { fail("Missing move destination.") }
        // Unlike mv, this refuses an existing directory instead of nesting apps.
        try FileManager.default.moveItem(atPath: arguments[1], toPath: arguments[2])
    case "stop":
        guard arguments.count == 3 else { fail("Missing bundle identifier.") }
        let copies = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == arguments[2] }
        guard copies.allSatisfy({ $0.bundleURL?.path == arguments[1] }) else {
            fail("Another MenuPocket copy is running. Quit that copy, then rerun install.sh.")
        }
        for app in copies {
            guard app.terminate() else { fail("MenuPocket refused to quit; app was not replaced.") }
            let deadline = Date().addingTimeInterval(10)
            while !app.isTerminated && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            guard app.isTerminated else { fail("MenuPocket did not quit; app was not replaced.") }
        }
    default: fail("Unknown app operation.")
    }
} catch { fail(error.localizedDescription) }
SWIFT
/usr/bin/xcrun swiftc -swift-version 5 -target "$(/usr/bin/uname -m)-apple-macos14.0" \
    "$run_dir/AppTool.swift" -framework AppKit -o "$app_tool"
echo "Building MenuPocket Release…"
echo "Build log: $run_dir/build.log"
/usr/bin/xcodebuild -quiet \
    -project "$project_dir/MenuPocket.xcodeproj" -scheme MenuPocket \
    -configuration Release -destination "platform=macOS,arch=$(/usr/bin/uname -m)" \
    -derivedDataPath "$run_dir/DerivedData" SDK_STAT_CACHE_ENABLE=NO build \
    >"$run_dir/build.log" 2>&1 || { /usr/bin/tail -n 30 "$run_dir/build.log" >&2; fail "Build failed; installed app was not replaced."; }

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$built_app/Contents/Info.plist")" == "$bundle_id" ]] || fail "Unexpected build product."
/usr/bin/codesign --verify --deep --strict "$built_app"
built_hash="$(/usr/bin/shasum -a 256 "$built_app/Contents/MacOS/MenuPocket" | /usr/bin/awk '{print $1}')"
/bin/mkdir "$staged_app" || fail "Staging path already exists; leaving it untouched."
staged_owned=1
/usr/bin/ditto "$built_app" "$staged_app"
/usr/bin/codesign --verify --deep --strict "$staged_app"

echo "Quitting the installed MenuPocket…"
"$app_tool" stop "$target_app" "$bundle_id"

saved_data() {
    /usr/bin/python3 - "$project_dir" "$backup_dir" "$1" <<'PY'
import hashlib, json, pathlib, re, shutil, sqlite3, sys
project, backup, phase = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
backup.mkdir(parents=True, exist_ok=True)
source = (project / 'MenuPocket/Notes/SQLiteNoteRepository.swift').read_text()
maximum = int(re.search(r'static let schemaVersion = (\d+)', source).group(1))
library = pathlib.Path.home() / 'Library'
roots = {'sandbox': library / 'Containers/local.menupocket.app/Data/Library', 'legacy': library}
record = {}
for label, root in roots.items():
    database = root / 'Application Support/MenuPocket/notes.sqlite'
    if database.exists():
        with sqlite3.connect(database.as_uri() + '?mode=ro', uri=True) as connection:
            version = connection.execute('PRAGMA user_version').fetchone()[0]
            if not 0 <= version <= maximum:
                raise SystemExit(f'Refusing to install over newer/unsupported schema {version}.')
            if connection.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise SystemExit(f'Database integrity check failed: {database}')
            logical = '\n'.join(connection.iterdump()).encode()
            record[label + '-database'] = {'schema': version, 'sha256': hashlib.sha256(logical).hexdigest()}
            if phase == 'before':
                with sqlite3.connect(backup / (label + '-notes.sqlite')) as destination:
                    connection.backup(destination)
                    if destination.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                        raise SystemExit('Backup integrity check failed.')
    preferences = root / 'Preferences/local.menupocket.app.plist'
    if preferences.exists():
        record[label + '-preferences'] = hashlib.sha256(preferences.read_bytes()).hexdigest()
        if phase == 'before':
            shutil.copy2(preferences, backup / (label + '-preferences.plist'))
if phase == 'after' and record != json.loads((backup / 'before.json').read_text()):
    raise SystemExit('Saved data/preferences changed during installation; previous app will be restored.')
(backup / (phase + '.json')).write_text(json.dumps(record, indent=2))
PY
}

echo "Backing up saved data…"
saved_data before
if [[ -e "$target_app" ]]; then
    old_trash="$(trash_app "$target_app")"
fi
# Stage and destination share a filesystem; the final move does not merge apps.
"$app_tool" move "$staged_app" "$target_app"
[[ ! -e "$staged_app" ]] || fail "Destination appeared during installation; refusing to overwrite it."
installed=1
/usr/bin/codesign --verify --deep --strict "$target_app"
[[ "$(/usr/bin/shasum -a 256 "$target_app/Contents/MacOS/MenuPocket" | /usr/bin/awk '{print $1}')" == "$built_hash" ]] || fail "Installed executable differs from the build."
saved_data after
committed=1
"$lsregister" -f "$target_app" >/dev/null 2>&1 || true
echo "Installed: $target_app"
echo "Data backup: $backup_dir"
[[ -z "$old_trash" ]] || echo "Previous app (recoverable): $old_trash"
if [[ $open_app == 1 ]]; then
    /usr/bin/open "$target_app" || fail "Installed successfully, but launch failed. Open $target_app manually."
fi
