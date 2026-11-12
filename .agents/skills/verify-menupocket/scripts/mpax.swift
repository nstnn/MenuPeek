// mpax: a small Accessibility driver for one process (the verify-menupocket
// fixture). It finds elements by AXIdentifier or visible label, performs AX
// actions, types through key events posted to that PID only, and captures
// window or element screenshots. Built by `fixture.sh build`; run it through
// `fixture.sh ax <run> ...`, which supplies the fixture PID.
//
// Queries: comma-separated terms, all of which must match (escape a literal comma as \,).
//   id=X      AXIdentifier equals X        id^=X   identifier starts with X
//   label=X   title, description, or value equals X
//   label~=X  title, description, or value contains X (case-insensitive)
//   role=X    AXRole equals X (AXButton, AXCheckBox, AXTextField, AXMenuItem, ...)
//   subrole=X AXSubrole equals X (AXCloseButton, AXSwitch, AXSegment, ...)
//   status-item   the fixture's menu bar status item
// Append #N to pick the Nth match (1-based). Windows, sheets, open menus and
// the status item are searched; the main menu bar only through `menu-path`.
import AppKit
import ApplicationServices

setvbuf(stdout, nil, _IONBF, 0)

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("mpax: \(message)\n".utf8))
    exit(code)
}

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func string(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else { return nil }
    if let text = value as? String { return text }
    if let number = value as? NSNumber { return number.stringValue }
    if CFGetTypeID(value) == AXValueGetTypeID() { return nil }
    return nil
}

func children(_ element: AXUIElement) -> [AXUIElement] {
    (attribute(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute),
          let size = attribute(element, kAXSizeAttribute) else { return nil }
    var point = CGPoint.zero, extent = CGSize.zero
    AXValueGetValue(position as! AXValue, .cgPoint, &point)
    AXValueGetValue(size as! AXValue, .cgSize, &extent)
    return CGRect(origin: point, size: extent)
}

func actions(_ element: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

func describe(_ element: AXUIElement) -> String {
    var parts = [string(element, kAXRoleAttribute) ?? "?"]
    if let subrole = string(element, kAXSubroleAttribute) { parts[0] += "/" + subrole }
    func clip(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: "⏎")
        return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
    }
    if let title = string(element, kAXTitleAttribute), !title.isEmpty { parts.append("title=\"\(clip(title))\"") }
    if let label = string(element, kAXDescriptionAttribute), !label.isEmpty { parts.append("label=\"\(clip(label))\"") }
    if let value = string(element, kAXValueAttribute), !value.isEmpty { parts.append("value=\"\(clip(value))\"") }
    if let id = string(element, kAXIdentifierAttribute), !id.isEmpty { parts.append("id=\(id)") }
    if let help = string(element, kAXHelpAttribute), !help.isEmpty { parts.append("help=\"\(clip(help))\"") }
    if (attribute(element, kAXEnabledAttribute) as? Bool) == false { parts.append("[disabled]") }
    if (attribute(element, kAXFocusedAttribute) as? Bool) == true { parts.append("[focused]") }
    if (attribute(element, kAXSelectedAttribute) as? Bool) == true { parts.append("[selected]") }
    return parts.joined(separator: " ")
}

struct Query {
    var terms: [(key: String, value: String)] = []
    var nth = 1
    var statusItem = false

    init(_ raw: String) {
        var text = raw
        if let hash = text.lastIndex(of: "#"), let n = Int(text[text.index(after: hash)...]), n > 0 {
            nth = n
            text = String(text[..<hash])
        }
        // Terms are comma-separated; write a literal comma inside a value as \,
        let placeholder = "\u{1F}"
        let parts = text.replacingOccurrences(of: "\\,", with: placeholder)
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.replacingOccurrences(of: placeholder, with: ",") }
        for term in parts {
            if term == "status-item" { statusItem = true; continue }
            guard let op = ["id^=", "label~=", "id=", "label=", "role=", "subrole="].first(where: term.hasPrefix) else {
                fail("unrecognized query term \"\(term)\" in \(raw) (escape a literal comma as \\,)", code: 64)
            }
            terms.append((String(op.dropLast()), String(term.dropFirst(op.count))))
        }
        if terms.isEmpty, !statusItem { fail("unrecognized query: \(raw)", code: 64) }
    }

    func matches(_ element: AXUIElement) -> Bool {
        terms.allSatisfy { key, value in
            switch key {
            case "id": return string(element, kAXIdentifierAttribute) == value
            case "id^": return string(element, kAXIdentifierAttribute)?.hasPrefix(value) == true
            case "role": return string(element, kAXRoleAttribute) == value
            case "subrole": return string(element, kAXSubroleAttribute) == value
            case "label", "label~":
                let texts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].compactMap { string(element, $0) }
                return key == "label" ? texts.contains(value)
                    : texts.contains { $0.localizedCaseInsensitiveContains(value) }
            default: return false
            }
        }
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
// `mpax trash <path>` (no PID): move a bundle to the Trash and print where it went.
if arguments.first == "trash", arguments.count == 2 {
    var resulting: NSURL?
    do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: arguments[1]), resultingItemURL: &resulting)
    } catch {
        fail("could not trash \(arguments[1]): \(error.localizedDescription)")
    }
    print(resulting?.path ?? "")
    exit(0)
}
guard arguments.count >= 2, let pid = pid_t(arguments[0]) else {
    fail("usage: mpax <pid> tree|find|press|action|actions|focus|set|type|key|wait|gone|value|menu-path|windows|screenshot|activate ...", code: 64)
}
guard AXIsProcessTrusted() else {
    fail("this process is not trusted for Accessibility; grant it to the terminal or agent app in System Settings > Privacy & Security > Accessibility", code: 77)
}
guard NSRunningApplication(processIdentifier: pid) != nil else { fail("no running application with pid \(pid)", code: 3) }
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5)
let command = arguments[1]
let rest = Array(arguments.dropFirst(2))

func roots() -> [AXUIElement] {
    var result = (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    // Open NSMenus: row "…" menus and pop-ups are children of the application;
    // the glance menu is a child of the status item.
    result += children(app).filter { string($0, kAXRoleAttribute) == kAXMenuRole }
    result += statusItems().flatMap(children)
    return result
}

func statusItems() -> [AXUIElement] {
    guard let extras = attribute(app, "AXExtrasMenuBar") else { return [] }
    return children(extras as! AXUIElement)
}

func search(_ query: Query) -> [AXUIElement] {
    if query.statusItem {
        return statusItems().filter { query.terms.isEmpty || query.matches($0) }
    }
    var found: [AXUIElement] = []
    var queue = roots()
    var visited = 0
    while !queue.isEmpty, visited < 20_000 {
        let element = queue.removeFirst()
        visited += 1
        if query.matches(element) { found.append(element) }
        queue += children(element)
    }
    return found
}

func element(_ raw: String, timeout: Double = 3) -> AXUIElement {
    let query = Query(raw)
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let found = search(query)
        if found.count >= query.nth { return found[query.nth - 1] }
        usleep(150_000)
    } while Date() < deadline
    fail("no element matches \(raw)", code: 2)
}

func perform(_ action: String, on target: AXUIElement, label: String) {
    let before = describe(target)
    let result = AXUIElementPerformAction(target, action as CFString)
    // A menu opened by the action keeps the target busy; the action still ran.
    guard result == .success || result == .cannotComplete else { fail("\(action) on \(label) failed: \(result.rawValue)") }
    let name = action.components(separatedBy: "\n").first ?? action
    print("\(name) on \(before)")
}

func dump(_ element: AXUIElement, depth: Int, limit: Int) {
    print(String(repeating: "  ", count: depth) + describe(element))
    guard depth < limit else { return }
    for child in children(element) { dump(child, depth: depth + 1, limit: limit) }
}

let keyCodes: [String: CGKeyCode] = [
    "return": 36, "enter": 76, "escape": 53, "tab": 48, "space": 49, "delete": 51,
    "up": 126, "down": 125, "left": 123, "right": 124, "home": 115, "end": 119,
    "a": 0, "c": 8, "e": 14, "n": 45, "q": 12, "v": 9, "w": 13, "x": 7, "z": 6,
    "1": 18, "2": 19, "0": 29, "comma": 43, "equal": 24, "minus": 27,
]

func post(_ code: CGKeyCode, flags: CGEventFlags = [], text: String? = nil) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { fail("cannot create key event") }
        event.flags = flags
        if let text {
            let units = Array(text.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        event.postToPid(pid)
        usleep(12_000)
    }
}

switch command {
case "tree":
    let limit = rest.first.flatMap(Int.init) ?? 40
    for item in statusItems() { print("status-item: " + describe(item)) }
    for root in roots() { dump(root, depth: 0, limit: limit) }
case "find":
    guard let raw = rest.first else { fail("find <query>", code: 64) }
    let found = search(Query(raw))
    for (index, item) in found.enumerated() { print("#\(index + 1) " + describe(item)) }
    if found.isEmpty { exit(2) }
case "press":
    guard let raw = rest.first else { fail("press <query>", code: 64) }
    perform(kAXPressAction, on: element(raw), label: raw)
case "actions":
    guard let raw = rest.first else { fail("actions <query>", code: 64) }
    for name in actions(element(raw)) { print(name.replacingOccurrences(of: "\n", with: " | ")) }
case "action":
    guard rest.count == 2 else { fail("action <query> <action-name-or-substring>", code: 64) }
    let target = element(rest[0])
    guard let name = actions(target).first(where: { $0 == rest[1] || $0.localizedCaseInsensitiveContains(rest[1]) }) else {
        fail("\(rest[0]) has no action matching \(rest[1]); it offers: \(actions(target))")
    }
    perform(name, on: target, label: rest[0])
case "focus":
    guard let raw = rest.first else { fail("focus <query>", code: 64) }
    let target = element(raw)
    let result = AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    guard result == .success else { fail("focus failed: \(result.rawValue)") }
    print("focused \(describe(target))")
case "set":
    guard rest.count == 2 else { fail("set <query> <text>", code: 64) }
    let target = element(rest[0])
    let result = AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, rest[1] as CFString)
    guard result == .success else { fail("set value failed: \(result.rawValue)") }
    print("set \(describe(target))")
case "type":
    guard let text = rest.first else { fail("type <text>", code: 64) }
    for character in text { post(0, text: String(character)) }
    print("typed \(text.count) characters")
case "key":
    guard let combo = rest.first?.lowercased() else { fail("key <combo>, e.g. return, escape, cmd+n", code: 64) }
    var flags: CGEventFlags = []
    let parts = combo.split(separator: "+").map(String.init)
    for modifier in parts.dropLast() {
        switch modifier {
        case "cmd": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: fail("unknown modifier \(modifier)", code: 64)
        }
    }
    guard let code = keyCodes[parts.last ?? ""] else { fail("unknown key \(parts.last ?? "") (known: \(keyCodes.keys.sorted()))", code: 64) }
    post(code, flags: flags)
    print("key \(combo)")
case "wait", "gone":
    guard let raw = rest.first else { fail("\(command) <query> [seconds]", code: 64) }
    let query = Query(raw)
    let deadline = Date().addingTimeInterval(rest.count > 1 ? Double(rest[1]) ?? 10 : 10)
    repeat {
        let present = search(query).count >= query.nth
        if present == (command == "wait") { print("\(command) ok: \(raw)"); exit(0) }
        usleep(200_000)
    } while Date() < deadline
    fail("\(command) timed out: \(raw)", code: 2)
case "frame":
    guard let raw = rest.first else { fail("frame <query>", code: 64) }
    guard let rect = frame(element(raw)) else { fail("no frame for \(raw)") }
    print("frame x=\(Int(rect.minX)) y=\(Int(rect.minY)) w=\(Int(rect.width)) h=\(Int(rect.height))")
case "value":
    guard let raw = rest.first else { fail("value <query>", code: 64) }
    print(describe(element(raw)))
case "menu-path":
    // Main menu bar, e.g. `menu-path View Later` or `menu-path MenuPocket "Settings…"`.
    guard rest.count >= 2, let bar = attribute(app, kAXMenuBarAttribute) else { fail("menu-path <top> <item> [<item>...]", code: 64) }
    var current = bar as! AXUIElement
    for (index, title) in rest.enumerated() {
        let pool = index == 0 ? children(current) : children(current).flatMap { children($0) + [$0] }
        guard let next = pool.first(where: { string($0, kAXTitleAttribute) == title }) else {
            fail("menu item \(title) not found")
        }
        if index == rest.count - 1 {
            if (attribute(next, kAXEnabledAttribute) as? Bool) == false { fail("menu item \(title) is disabled", code: 4) }
            perform(kAXPressAction, on: next, label: title)
        } else {
            current = next
        }
    }
case "windows":
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in info where (window[kCGWindowOwnerPID as String] as? pid_t) == pid {
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        print("window \(window[kCGWindowNumber as String] ?? "?") layer=\(window[kCGWindowLayer as String] ?? "?") onscreen=\(window[kCGWindowIsOnscreen as String] ?? false) name=\"\(window[kCGWindowName as String] ?? "")\" bounds=\(bounds)")
    }
case "screenshot":
    // screenshot <out.png> [query]: a matched window by its window ID, any other
    // element by its screen frame, or the fixture's frontmost titled window.
    guard let out = rest.first else { fail("screenshot <out.png> [query]", code: 64) }
    var captureArguments = ["-x", "-o"]
    let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    if rest.count > 1 {
        let target = element(rest[1])
        let title = string(target, kAXTitleAttribute)
        if string(target, kAXRoleAttribute) == kAXWindowRole, let window = info.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowName as String] as? String) == title
        }), let number = window[kCGWindowNumber as String] as? Int {
            // A window is captured by ID, so overlapping windows don't appear in it.
            captureArguments += ["-l", String(number)]
        } else {
            // Anything else (menus, the status item, a control) is a screen rectangle.
            guard let rect = frame(target) else { fail("element has no frame") }
            captureArguments += ["-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))"]
        }
    } else {
        let onScreen = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        guard let window = onScreen.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
                && !(($0[kCGWindowName as String] as? String) ?? "").isEmpty
        }), let number = window[kCGWindowNumber as String] as? Int else { fail("no on-screen window for pid \(pid)") }
        captureArguments += ["-l", String(number)]
    }
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = captureArguments + [out]
    try capture.run()
    capture.waitUntilExit()
    guard capture.terminationStatus == 0, FileManager.default.fileExists(atPath: out) else {
        fail("screencapture failed (Screen Recording permission?)")
    }
    print("screenshot \(out)")
case "activate":
    NSRunningApplication(processIdentifier: pid)?.activate()
    usleep(300_000)
    print("activated \(pid)")
default:
    fail("unknown command \(command)", code: 64)
}
