import Foundation
import OSLog
import ServiceManagement

enum LoginItemStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    init(systemStatus: SMAppService.Status) {
        switch systemStatus {
        case .notRegistered:
            self = .disabled
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }
}

enum LoginItemOperationFailure: Equatable, Sendable {
    case registrationFailed
    case unregistrationFailed

    var message: String {
        switch self {
        case .registrationFailed:
            "Không thể bật Mở khi đăng nhập. Hãy kiểm tra cài đặt Đăng nhập trong Cài đặt hệ thống rồi thử lại."
        case .unregistrationFailed:
            "Không thể tắt Mở khi đăng nhập. Hãy kiểm tra cài đặt Đăng nhập trong Cài đặt hệ thống rồi thử lại."
        }
    }
}

struct LoginItemOperationResult: Equatable, Sendable {
    let status: LoginItemStatus
    let failure: LoginItemOperationFailure?
}

protocol LoginItemService {
    func readStatus() -> LoginItemStatus
    func register() -> LoginItemOperationResult
    func unregister() -> LoginItemOperationResult
}

// This narrow boundary lets tests exercise the service without accessing the host's login items.
protocol LoginItemSystemAccess {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

private struct MainAppLoginItemSystem: LoginItemSystemAccess {
    var status: SMAppService.Status { SMAppService.mainApp.status }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

final class SystemLoginItemService: LoginItemService {
    private static let logger = Logger(
        subsystem: "local.menupocket.app",
        category: "LoginItem"
    )

    private let system: any LoginItemSystemAccess

    init(system: any LoginItemSystemAccess) {
        self.system = system
    }

    convenience init() {
        self.init(system: MainAppLoginItemSystem())
    }

    func readStatus() -> LoginItemStatus {
        LoginItemStatus(systemStatus: system.status)
    }

    func register() -> LoginItemOperationResult {
        do {
            try system.register()
            return LoginItemOperationResult(status: readStatus(), failure: nil)
        } catch {
            Self.logger.error("Login-item registration failed: \(error.localizedDescription, privacy: .public)")
            return LoginItemOperationResult(status: readStatus(), failure: .registrationFailed)
        }
    }

    func unregister() -> LoginItemOperationResult {
        do {
            try system.unregister()
            return LoginItemOperationResult(status: readStatus(), failure: nil)
        } catch {
            Self.logger.error("Login-item unregistration failed: \(error.localizedDescription, privacy: .public)")
            return LoginItemOperationResult(status: readStatus(), failure: .unregistrationFailed)
        }
    }
}
