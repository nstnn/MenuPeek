import Foundation
import OSLog

enum PreferencesWarning: Equatable, Sendable {
    case corruptData
    case newerSchema(storedVersion: Int, supportedVersion: Int)

    var message: String {
        switch self {
        case .corruptData:
            "Could not read saved preferences. MenuPocket is using defaults for this session; other settings were not changed."
        case let .newerSchema(storedVersion, supportedVersion):
            "Saved preferences use version \(storedVersion), newer than this app supports (\(supportedVersion)). They are protected from changes in this session. Use a compatible MenuPocket version to edit them; saved data was preserved."
        }
    }
}

enum PreferencesLoadOutcome: Equatable, Sendable {
    case initializedDefaults(AppPreferences)
    case loaded(AppPreferences)
    case recovered(AppPreferences, warning: PreferencesWarning)
    case incompatibleSchema(AppPreferences, warning: PreferencesWarning)

    var preferences: AppPreferences {
        switch self {
        case let .initializedDefaults(preferences),
             let .loaded(preferences),
             let .recovered(preferences, _),
             let .incompatibleSchema(preferences, _):
            preferences
        }
    }

    var warning: PreferencesWarning? {
        switch self {
        case .initializedDefaults, .loaded:
            nil
        case let .recovered(_, warning), let .incompatibleSchema(_, warning):
            warning
        }
    }

    var allowsPersistence: Bool {
        if case .incompatibleSchema = self {
            false
        } else {
            true
        }
    }
}

enum PreferencesSaveOutcome: Equatable, Sendable {
    case saved
    case writeProtected(PreferencesWarning)
}

protocol PreferencesStoring {
    func load() throws -> PreferencesLoadOutcome
    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome
}

final class PreferencesStore: PreferencesStoring {
    static let storageKey = "local.menupocket.app.preferences"

    private struct SchemaEnvelope: Decodable {
        let schemaVersion: Int
    }

    private static let logger = Logger(
        subsystem: "local.menupocket.app",
        category: "Preferences"
    )

    private let userDefaults: UserDefaults
    private let defaultPreferences: AppPreferences
    private let reconciler: PreferencesReconciler
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var writeProtectionWarning: PreferencesWarning?

    init(
        userDefaults: UserDefaults = .standard,
        defaultPreferences: AppPreferences = .defaultValue,
        catalog: [ModuleDescriptor] = ModuleCatalog.defaultModules
    ) {
        self.userDefaults = userDefaults
        self.defaultPreferences = defaultPreferences
        reconciler = PreferencesReconciler(catalog: catalog)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
        decoder = JSONDecoder()
    }

    func load() throws -> PreferencesLoadOutcome {
        if let warning = writeProtectionWarning {
            return .incompatibleSchema(defaultPreferences, warning: warning)
        }

        guard let storedValue = userDefaults.object(forKey: Self.storageKey) else {
            _ = try save(defaultPreferences)
            return .initializedDefaults(defaultPreferences)
        }

        guard let data = storedValue as? Data else {
            Self.logger.error(
                "Stored preferences have an unexpected type; using session defaults without clearing other UserDefaults keys."
            )
            return .recovered(defaultPreferences, warning: .corruptData)
        }

        do {
            let schema = try decoder.decode(SchemaEnvelope.self, from: data)
            if schema.schemaVersion > AppPreferences.currentSchemaVersion {
                let warning = PreferencesWarning.newerSchema(
                    storedVersion: schema.schemaVersion,
                    supportedVersion: AppPreferences.currentSchemaVersion
                )
                writeProtectionWarning = warning
                Self.logger.warning(
                    "Preferences schema \(schema.schemaVersion) is newer than supported schema \(AppPreferences.currentSchemaVersion); preserving stored data and blocking writes for this session."
                )
                return .incompatibleSchema(defaultPreferences, warning: warning)
            }

            let preferences = try decoder.decode(AppPreferences.self, from: data)
            return .loaded(reconciler.reconcile(preferences))
        } catch {
            Self.logger.error(
                "Unable to decode stored preferences; using session defaults without clearing other UserDefaults keys: \(error.localizedDescription, privacy: .public)"
            )
            return .recovered(defaultPreferences, warning: .corruptData)
        }
    }

    @discardableResult
    func save(_ preferences: AppPreferences) throws -> PreferencesSaveOutcome {
        if let warning = writeProtectionWarning {
            return .writeProtected(warning)
        }

        if let data = userDefaults.data(forKey: Self.storageKey),
           let schema = try? decoder.decode(SchemaEnvelope.self, from: data),
           schema.schemaVersion > AppPreferences.currentSchemaVersion {
            let warning = PreferencesWarning.newerSchema(
                storedVersion: schema.schemaVersion,
                supportedVersion: AppPreferences.currentSchemaVersion
            )
            writeProtectionWarning = warning
            Self.logger.warning(
                "Refusing to overwrite preferences schema \(schema.schemaVersion) with supported schema \(AppPreferences.currentSchemaVersion)."
            )
            return .writeProtected(warning)
        }

        let data = try encoder.encode(reconciler.reconcile(preferences))
        userDefaults.set(data, forKey: Self.storageKey)
        return .saved
    }
}
