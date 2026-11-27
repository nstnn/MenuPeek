import Foundation
import XCTest

/// The test bundle's principal class (`NSPrincipalClass`), created once when
/// XCTest loads the bundle and before any test runs.
///
/// Hosted tests run in the app's sandbox container and give each test its own
/// defaults suite. `removePersistentDomain(forName:)` empties a suite, but
/// cfprefsd then writes an empty `<suite>.plist` into the container's
/// Library/Preferences, sometimes after the test process has exited, so a
/// test cannot delete it itself. Each run therefore removes the empty suite
/// files that earlier runs left behind.
///
/// Only files whose name starts with a test-suite prefix and whose contents are
/// an empty dictionary are removed. The app's own defaults, other domains, and
/// suites that still hold values (for example, a run in progress elsewhere)
/// are never touched.
@objc(MenuPocketTestDefaultsSweeper)
final class TestDefaultsSweeper: NSObject {
    /// Name prefixes of every defaults suite the tests create.
    static let suitePrefixes = [
        "local.menupocket.tests.",
        "AppConfigurationTests.",
        "HistorySummaryTests-",
        "ScheduleStateTests.",
        "TaskHistoryIntegrationTests.",
        "TaskHistoryStateTests.",
        "UnfinishedTasksStateTests.",
    ]

    override init() {
        super.init()
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let removed = Self.removeEmptySuiteFiles(in: library.appendingPathComponent("Preferences", isDirectory: true))
        if removed > 0 { print("TestDefaultsSweeper: removed \(removed) empty test defaults files") }
    }

    /// Removes leftover empty test-suite plists in `directory` and returns how many.
    @discardableResult
    static func removeEmptySuiteFiles(in directory: URL, fileManager: FileManager = .default) -> Int {
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for name in names where isTestSuiteFile(name) {
            let file = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? NSDictionary,
                  plist.count == 0 else { continue }
            if (try? fileManager.removeItem(at: file)) != nil { removed += 1 }
        }
        return removed
    }

    static func isTestSuiteFile(_ name: String) -> Bool {
        name.hasSuffix(".plist") && suitePrefixes.contains { name.hasPrefix($0) }
    }
}

final class TestDefaultsSweeperTests: XCTestCase {
    func testRemovesOnlyEmptyTestSuiteFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestDefaultsSweeperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        func write(_ name: String, _ values: [String: Any]) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try data.write(to: directory.appendingPathComponent(name))
        }
        try write("local.menupocket.tests.Lifecycle.A.plist", [:])
        try write("HistorySummaryTests-B.plist", [:])
        try write("local.menupocket.tests.Lifecycle.InUse.plist", ["key": "value"])
        try write("local.menupocket.app.plist", [:])
        try write("com.apple.security.plist", [:])
        try Data("not a plist".utf8).write(to: directory.appendingPathComponent("ScheduleStateTests.C.plist"))

        XCTAssertEqual(TestDefaultsSweeper.removeEmptySuiteFiles(in: directory), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), [
            "ScheduleStateTests.C.plist",
            "com.apple.security.plist",
            "local.menupocket.app.plist",
            "local.menupocket.tests.Lifecycle.InUse.plist",
        ])
    }
}
