import Foundation

@MainActor
protocol OnboardingStoring {
    var hasCompletedOnboarding: Bool { get }
    func markOnboardingCompleted()
}

@MainActor
final class UserDefaultsOnboardingStore: OnboardingStoring {
    static let storageKey = "local.menupocket.app.onboardingCompleted"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var hasCompletedOnboarding: Bool {
        userDefaults.bool(forKey: Self.storageKey)
    }

    func markOnboardingCompleted() {
        userDefaults.set(true, forKey: Self.storageKey)
    }
}
