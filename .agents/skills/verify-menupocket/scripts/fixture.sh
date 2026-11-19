#!/bin/bash
# verify-menupocket fixture control. Run from anywhere:
#   fixture.sh build                          compile a fixture app + mpax driver, print RUN=<id>
#   fixture.sh launch <run> [--seed empty|basic|category-reordering|calendar] [--now ISO8601] [--tz ZONE]
#   fixture.sh doctor <run>                   read-only health check
#   fixture.sh ax <run> <mpax command...>     drive the fixture (logged to actions.log)
#   fixture.sh snapshot <run> <label>         DB rows, defaults, AX tree, screenshot -> evidence
#   fixture.sh quickadd <run>                 press the fake Quick Add hotkey (SIGUSR1)
#   fixture.sh next-day <run>                 advance the fixture clock one day (SIGUSR2)
#   fixture.sh fail-open <run> on|off         make opening storage fail on the next open
#   fixture.sh stop <run> [--force]           quit like Command-Q; --force kills that exact PID
#   fixture.sh cleanup <run>                  stop, trash + unregister the app, drop scratch state
# Runs live in build/verify-menupocket/runs/<run>; evidence in
# build/verify-menupocket/evidence/<run> and survives cleanup.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(git -C "$script_dir" rev-parse --show-toplevel)"
base="$repo/build/verify-menupocket"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

die() { echo "fixture.sh: $*" >&2; exit 1; }

load_run() {
    run="${1:-}"
    [[ -n "$run" ]] || die "missing run id (printed by 'fixture.sh build' as RUN=...)"
    run_dir="$base/runs/$run"
    evidence="$base/evidence/$run"
    bundle="$run_dir/MenuPocketVerify.app"
    executable="$bundle/Contents/MacOS/MenuPocketVerify"
    data="$run_dir/data"
    bundle_id="local.menupocket.verify.r$run"
    suite="$bundle_id.defaults"
    mpax="$run_dir/bin/mpax"
    pid_file="$data/fixture.pid"
}

# Prints the PID only when it is alive and runs this run's executable. Without a
# valid pid file (for example after a launch timed out), it looks for a process
# running this run's executable; that path is unique to the run.
running_pid() {
    local pid command
    if [[ -f "$pid_file" ]]; then
        pid="$(cat "$pid_file")"
        command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        if [[ "$command" == "$executable"* ]]; then echo "$pid"; return 0; fi
    fi
    pid="$(ps -axo pid=,command= | awk -v exe="$executable" '
        { pid = $1; sub(/^ *[0-9]+ +/, ""); if (index($0, exe) == 1) { print pid; exit } }')"
    [[ -n "$pid" && -d "$data" ]] || return 1
    echo "$pid" >"$pid_file"
    echo "$pid"
}

cmd_build() {
    local run; run="$(date +%Y%m%d-%H%M%S)"
    load_run "$run"
    mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources" "$run_dir/bin" "$data" "$evidence"
    local arch; arch="$(uname -m)"
    local sources=()
    while IFS= read -r file; do sources+=("$file"); done < <(cd "$repo" && find MenuPocket -name '*.swift' ! -name MenuPocketApp.swift | sort)

    echo "Building fixture from ${#sources[@]} app sources (log: $run_dir/build.log)…"
    (cd "$repo" && xcrun swiftc -swift-version 6 -parse-as-library -module-name MenuPocketVerify \
        -target "$arch-apple-macos14.0" -module-cache-path "$run_dir/cache" \
        -framework AppKit -framework SwiftUI -framework ServiceManagement -framework Carbon -lsqlite3 \
        "${sources[@]}" "$script_dir/FixtureMain.swift" -o "$executable") >"$run_dir/build.log" 2>&1 \
        || { tail -30 "$run_dir/build.log" >&2; die "fixture compile failed; the working tree must compile first"; }
    xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" -module-cache-path "$run_dir/cache" \
        "$script_dir/mpax.swift" -o "$mpax" >>"$run_dir/build.log" 2>&1 \
        || { tail -30 "$run_dir/build.log" >&2; die "mpax compile failed"; }

    local icon_keys=""
    if xcrun actool "$repo/MenuPocket/Assets.xcassets" --compile "$bundle/Contents/Resources" \
        --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "$run_dir/assets-info.plist" >>"$run_dir/build.log" 2>&1; then
        icon_keys="<key>CFBundleIconName</key><string>AppIcon</string><key>CFBundleIconFile</key><string>AppIcon</string>"
    fi
    cat >"$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>MenuPocket Verify</string>
<key>CFBundleDisplayName</key><string>MenuPocket Verify</string>
<key>CFBundleExecutable</key><string>MenuPocketVerify</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0-verify</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
$icon_keys
</dict></plist>
PLIST
    codesign --force --sign - "$bundle" >>"$run_dir/build.log" 2>&1

    local dirty; dirty="$(cd "$repo" && git status --porcelain -- MenuPocket | awk '{print $2}' | paste -sd, -)"
    cat >"$evidence/identity.json" <<JSON
{
  "run": "$run",
  "source_revision": "$(git -C "$repo" rev-parse HEAD)",
  "dirty_app_sources": "${dirty}",
  "app_sources_sha256": "$(cd "$repo" && cat "${sources[@]}" | shasum -a 256 | cut -d' ' -f1)",
  "bundle": "$bundle",
  "bundle_id": "$bundle_id",
  "executable_sha256": "$(shasum -a 256 "$executable" | cut -d' ' -f1)",
  "database": "$data/fixture.sqlite",
  "defaults_suite": "$suite",
  "login_item": "fake: always disabled",
  "quick_add_hotkey": "fake: never registered with Carbon; SIGUSR1 presses it",
  "swiftc": "$(xcrun swiftc --version 2>&1 | head -1)"
}
JSON
    echo "Built $bundle"
    echo "RUN=$run"
}

cmd_launch() {
    load_run "$1"; shift
    [[ -x "$executable" ]] || die "no fixture for run $run; run 'fixture.sh build' first"
    if pid="$(running_pid)"; then die "run $run is already running as PID $pid"; fi
    local seed=empty extra=()
    while (($#)); do
        case "$1" in
            --seed) seed="$2"; shift 2 ;;
            --now|--tz) extra+=("$1" "$2"); shift 2 ;;
            *) die "unknown launch option $1" ;;
        esac
    done
    local data_note="seed=$seed"
    [[ -f "$data/fixture.sqlite" ]] && data_note="existing data kept (--seed ignored)"
    rm -f "$pid_file"
    /usr/bin/open -n "$bundle" --stdout "$run_dir/fixture.log" --stderr "$run_dir/fixture.log" \
        --args --data "$data" --defaults-suite "$suite" --seed "$seed" ${extra[@]+"${extra[@]}"}
    # The first launch of a freshly signed bundle can take tens of seconds while
    # macOS assesses it; later launches take about a second.
    local pid="" attempt
    for attempt in $(seq 1 600); do
        if [[ -f "$data/launched.pid" ]]; then
            pid="$(cat "$data/launched.pid")"
            break
        fi
        sleep 0.1
    done
    [[ -n "$pid" ]] || { cat "$run_dir/fixture.log" >&2 || true; die "fixture did not report a PID within 60 s; run 'fixture.sh doctor $run' before launching again"; }
    echo "$pid" >"$pid_file"
    running_pid >/dev/null || die "PID $pid is not this run's executable"
    "$mpax" "$pid" wait status-item 15 >/dev/null || die "status item never appeared"
    "$mpax" "$pid" wait id=todayTab 15 >/dev/null || die "task window never appeared"
    echo "Ready: PID $pid, status item: $("$mpax" "$pid" value status-item)"
    echo "$(date '+%T') launch pid=$pid $data_note ${extra[*]:-}" >>"$evidence/actions.log"
}

cmd_doctor() {
    load_run "$1"
    local ok=1
    check() { if eval "$2"; then echo "ok    $1"; else echo "FAIL  $1"; ok=0; fi; }
    check "fixture bundle exists ($bundle)" '[[ -x "$executable" ]]'
    check "executable matches identity.json hash" \
        '[[ "$(shasum -a 256 "$executable" 2>/dev/null | cut -d" " -f1)" == "$(sed -n "s/.*\"executable_sha256\": \"\(.*\)\".*/\1/p" "$evidence/identity.json")" ]]'
    local pid=""; pid="$(running_pid || true)"
    check "fixture process is running from this run's bundle" '[[ -n "$pid" ]]'
    if [[ -n "$pid" ]]; then
        local open_files; open_files="$(lsof -p "$pid" -Fn 2>/dev/null | sed -n 's/^n//p')"
        check "the run's fixture.sqlite is open" 'grep -qx "$data/fixture.sqlite" <<<"$open_files"'
        check "no production MenuPocket data is open" '! grep -q "Containers/local.menupocket.app" <<<"$open_files"'
        check "Accessibility driver works and sees the status item" '"$mpax" "$pid" value status-item >/dev/null 2>&1'
        check "task window exists" '"$mpax" "$pid" find id=todayTab >/dev/null 2>&1'
        echo "info  status item: $("$mpax" "$pid" value status-item 2>/dev/null || echo unavailable)"
    fi
    echo "info  other MenuPocket processes (not touched): $(pgrep -lf 'MenuPocket.app/Contents/MacOS/MenuPocket' | paste -sd';' - || echo none)"
    ((ok)) || exit 1
}

cmd_ax() {
    load_run "$1"; shift
    local pid; pid="$(running_pid)" || die "run $run is not running"
    local output status=0
    output="$("$mpax" "$pid" "$@" 2>&1)" || status=$?
    printf '%s\n' "$output"
    if [[ "${1:-}" != tree && "${1:-}" != find && "${1:-}" != windows ]]; then
        printf '%s ax %s -> %s%s\n' "$(date '+%T')" "$*" "$(head -1 <<<"$output")" \
            "$( ((status)) && echo " [exit $status]")" >>"$evidence/actions.log"
    fi
    return "$status"
}

cmd_snapshot() {
    load_run "$1"
    local label="${2:?snapshot needs a label}"
    mkdir -p "$evidence/snapshots"
    local count; count="$(find "$evidence/snapshots" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
    local out; out="$evidence/snapshots/$(printf '%02d' $((count + 1)))-$label"
    mkdir -p "$out"
    if [[ -f "$data/fixture.sqlite" ]]; then
        sqlite3 -readonly -cmd ".timeout 5000" "$data/fixture.sqlite" >"$out/db.txt" 2>&1 <<'SQL' || {
.headers on
.mode column
SELECT user_version AS schema_version FROM pragma_user_version;
SELECT rowid, * FROM categories ORDER BY creation_order;
SELECT n.rowid, n.id, n.day_key, n.display_order, n.text, n.completed_at IS NOT NULL AS done, n.continued_on, COALESCE(c.name, 'General') AS category
  FROM notes n LEFT JOIN categories c ON c.id = n.category_id ORDER BY n.day_key, n.display_order;
SELECT l.rowid, l.text, l.completed_at IS NOT NULL AS done, COALESCE(c.name, 'General') AS category
  FROM later_tasks l LEFT JOIN categories c ON c.id = l.category_id ORDER BY l.rowid;
SELECT rowid, id, day_key, start_minute, end_minute,
       printf('%02d:%02d-%02d:%02d', start_minute / 60, start_minute % 60, end_minute / 60, end_minute % 60) AS times, title
  FROM schedule_blocks ORDER BY day_key, start_minute, created_at, id;
SQL
            echo "-- a query failed (schema changed?); full dump follows" >>"$out/db.txt"
            sqlite3 -readonly -cmd ".timeout 5000" "$data/fixture.sqlite" .dump >>"$out/db.txt"
        }
    fi
    if defaults export "$suite" - >"$out/defaults.plist" 2>/dev/null; then
        # AppPreferences is stored as JSON data; decode it so the diff is readable.
        /usr/bin/python3 -I -c 'import plistlib, sys
value = plistlib.load(open(sys.argv[1], "rb")).get("local.menupocket.app.preferences")
sys.stdout.write(value.decode() + "\n" if value else "")' "$out/defaults.plist" >"$out/preferences.json" 2>/dev/null || true
        [[ -s "$out/preferences.json" ]] || rm -f "$out/preferences.json"
    else
        echo "(no defaults written)" >"$out/defaults.plist"
    fi
    local pid
    if pid="$(running_pid)"; then
        "$mpax" "$pid" tree >"$out/ax-tree.txt" 2>&1 || true
        "$mpax" "$pid" screenshot "$out/window.png" >/dev/null 2>&1 || echo "no on-screen window" >"$out/window.txt"
    else
        echo "fixture not running" >"$out/ax-tree.txt"
    fi
    echo "$(date '+%T') snapshot $out" >>"$evidence/actions.log"
    echo "$out"
}

cmd_signal() {
    load_run "$1"
    local pid; pid="$(running_pid)" || die "run $run is not running"
    kill "-$2" "$pid"
    sleep 0.5
    echo "$(date '+%T') signal $2 ($3)" >>"$evidence/actions.log"
    tail -1 "$run_dir/fixture.log"
}

cmd_fail_open() {
    load_run "$1"
    case "${2:-}" in
        on) touch "$data/fail-open" ;;
        off) rm -f "$data/fail-open" ;;
        *) die "fail-open <run> on|off" ;;
    esac
    echo "$(date '+%T') fail-open $2" >>"$evidence/actions.log"
}

cmd_stop() {
    load_run "$1"
    local pid; pid="$(running_pid)" || { echo "run $run is not running"; return 0; }
    # NSRunningApplication.terminate is the same quit request as Command-Q.
    /usr/bin/osascript -l JavaScript -e "ObjC.import('AppKit'); \$.NSRunningApplication.runningApplicationWithProcessIdentifier($pid).terminate" >/dev/null
    local attempt
    for attempt in $(seq 1 50); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
        [[ "${2:-}" == --force ]] || die "PID $pid did not quit; rerun with --force to kill it"
        kill -9 "$pid"
        echo "$(date '+%T') stop pid=$pid forced" >>"$evidence/actions.log"
    else
        echo "$(date '+%T') stop pid=$pid quit" >>"$evidence/actions.log"
    fi
    rm -f "$pid_file" "$data/launched.pid"
    cp "$run_dir/fixture.log" "$evidence/fixture.log" 2>/dev/null || true
    echo "Stopped PID $pid"
}

registered_paths() {
    "$lsregister" -dump 2>/dev/null | awk -v id="$bundle_id" '
        /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
        /^identifier:/ && $2 == id { print path }' | sort -u
}

# Trash copies of any earlier verify run. macOS can register a trashed bundle
# again minutes after cleanup; these copies are inert and safe to unregister.
stale_trash_paths() {
    "$lsregister" -dump 2>/dev/null | awk -v trash="$HOME/.Trash/" '
        /^path:/ { sub(/^path:[ \t]+/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
        /^identifier:/ && $2 ~ /^local\.menupocket\.verify\.r/ && index(path, trash) == 1 { print path }' | sort -u
}

cmd_cleanup() {
    load_run "$1"
    [[ -d "$run_dir" ]] || { echo "run $run has no scratch state left"; return 0; }
    [[ -x "$mpax" ]] || die "missing $mpax; rebuild it before cleaning up (see SKILL.md Cleanup)"
    cmd_stop "$run" --force
    local report="$evidence/cleanup.txt"
    {
        echo "cleanup $(date '+%F %T')"
        cp "$run_dir/build.log" "$evidence/build.log" 2>/dev/null || true
        cp "$run_dir/fixture.log" "$evidence/fixture.log" 2>/dev/null || true
        if [[ -e "$bundle" ]]; then
            "$lsregister" -u "$bundle" 2>&1 || true
            local trashed; trashed="$("$mpax" trash "$bundle")" || { echo "FAIL could not move $bundle to Trash"; return 1; }
            echo "trashed $bundle -> $trashed"
            "$lsregister" -u "$trashed" 2>&1 || true
            echo "unregistered $trashed"
        fi
        # The bundle ID is unique to this run, so every path registered under it
        # (the original, the Trash copy) belongs to this run. macOS registers the
        # Trash copy once more a few seconds after the move; keep watching until
        # that has been caught and removed (each dump takes a few seconds).
        local path attempt found cleared=0
        for attempt in 1 2 3 4 5 6; do
            found=0
            while IFS= read -r path; do
                [[ -n "$path" ]] || continue
                found=1
                "$lsregister" -u "$path" 2>&1 || true
                echo "unregistered $path"
            done < <(registered_paths)
            ((found)) && cleared=1
            ((cleared && !found)) && break
            sleep 1
        done
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            "$lsregister" -u "$path" 2>&1 || true
            echo "unregistered Trash copy $path"
        done < <(stale_trash_paths)
        defaults delete "$suite" 2>/dev/null && echo "deleted defaults suite $suite" || true
        defaults delete "$bundle_id" 2>/dev/null && echo "deleted defaults domain $bundle_id" || true
        rm -f "$HOME/Library/Preferences/$suite.plist" "$HOME/Library/Preferences/$bundle_id.plist"
        rm -rf "$HOME/Library/Saved Application State/$bundle_id.savedState" "$HOME/Library/Caches/$bundle_id" \
            "$HOME/Library/HTTPStorages/$bundle_id"
        rm -rf "$run_dir"
        echo "removed $run_dir"
        echo "-- verification"
        [[ ! -e "$bundle" ]] && echo "ok    original bundle path is gone" || echo "FAIL  bundle still at $bundle"
        local left; left="$(registered_paths | paste -sd';' -)"
        [[ -z "$left" ]] && echo "ok    LaunchServices has no path for $bundle_id" || echo "WARN  LaunchServices still lists: $left"
        [[ ! -e "$HOME/Library/Preferences/$suite.plist" ]] && echo "ok    defaults suite removed" || echo "WARN  $suite.plist remains"
        echo "info  spotlight: $(mdfind "kMDItemCFBundleIdentifier == '$bundle_id'" | paste -sd';' -)"
        echo "info  processes: $(pgrep -lf "$run_dir" || echo none)"
    } 2>&1 | tee "$report"
    echo "Evidence kept in $evidence"
}

case "${1:-}" in
    build) cmd_build ;;
    launch) shift; cmd_launch "$@" ;;
    doctor) cmd_doctor "${2:-}" ;;
    ax) shift; cmd_ax "$@" ;;
    snapshot) cmd_snapshot "${2:-}" "${3:-}" ;;
    quickadd) cmd_signal "${2:-}" USR1 "Quick Add hotkey" ;;
    next-day) cmd_signal "${2:-}" USR2 "next day" ;;
    fail-open) cmd_fail_open "${2:-}" "${3:-}" ;;
    stop) cmd_stop "${2:-}" "${3:-}" ;;
    cleanup) cmd_cleanup "${2:-}" ;;
    *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 64 ;;
esac
