import Foundation

struct ModuleRuntimeState: Equatable {
    var snapshot: ModuleSnapshot?
    var isLoading = false
    var lastError: String?
    var hasCompletedAttempt = false
}
