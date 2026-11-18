import AppKit
import Foundation
import Observation
import SwiftUI

/// The task window's content zoom on this Mac (View > Zoom In ⌘+, Zoom Out ⌘−,
/// Actual Size ⌘0). Kept in its own defaults key, apart from the versioned
/// AppPreferences envelope. A missing or unrecognized value means Actual Size.
@MainActor
@Observable
final class TaskWindowZoom {
    nonisolated static let storageKey = "local.menupocket.app.taskWindow.zoom"
    nonisolated static let levels: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
    nonisolated static let actualSize = 1.0

    private(set) var scale: Double

    @ObservationIgnored private let userDefaults: UserDefaults

    /// Reads without writing, so an unrecognized value stays untouched until
    /// the zoom changes.
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = (userDefaults.object(forKey: Self.storageKey) as? NSNumber)?.doubleValue
        scale = stored.flatMap(Self.level(matching:)) ?? Self.actualSize
    }

    var isActualSize: Bool { scale == Self.actualSize }

    /// The zoom as a whole percentage, e.g. "110%". Actual Size is "100%".
    var percentText: String { Self.percentText(for: scale) }

    nonisolated static func percentText(for scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
    var nextLarger: Double? { Self.levels.first { $0 > scale } }
    var nextSmaller: Double? { Self.levels.last { $0 < scale } }

    /// Moves one level up. `fits` rejects a level the window cannot show on
    /// its screen. Returns whether the zoom changed.
    @discardableResult
    func zoomIn(fits: (Double) -> Bool = { _ in true }) -> Bool {
        guard let next = nextLarger, fits(next) else { return false }
        set(next)
        return true
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard let next = nextSmaller else { return false }
        set(next)
        return true
    }

    @discardableResult
    func resetToActualSize() -> Bool {
        guard !isActualSize else { return false }
        set(Self.actualSize)
        return true
    }

    private func set(_ value: Double) {
        scale = value
        if value == Self.actualSize {
            userDefaults.removeObject(forKey: Self.storageKey)
        } else {
            userDefaults.set(value, forKey: Self.storageKey)
        }
    }

    nonisolated private static func level(matching value: Double) -> Double? {
        levels.first { abs($0 - value) < 0.001 }
    }
}

/// Lays the content out at the window size divided by the zoom, then scales
/// the rendering back up to fill the window, like page zoom in a browser.
struct TaskWindowZoomContainer<Content: View>: View {
    let zoom: TaskWindowZoom
    @ViewBuilder let content: Content

    /// Bumped on each zoom change; the indicator shows while it is current.
    @State private var indicatorGeneration = 0
    @State private var isIndicatorVisible = false

    var body: some View {
        let scale = CGFloat(zoom.scale)
        GeometryReader { geometry in
            content
                .frame(width: geometry.size.width / scale, height: geometry.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
        // Outside the scale effect, so the indicator keeps one size at every zoom.
        .overlay(alignment: .top) {
            if isIndicatorVisible {
                TaskWindowZoomIndicator(text: zoom.percentText, isActualSize: zoom.isActualSize)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
        .onChange(of: zoom.scale) { _, _ in
            indicatorGeneration += 1
            withAnimation(.easeOut(duration: 0.12)) { isIndicatorVisible = true }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: "Zoom \(zoom.percentText)",
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        .task(id: indicatorGeneration) {
            guard indicatorGeneration > 0 else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.25)) { isIndicatorVisible = false }
        }
    }
}

/// A short-lived pill naming the current zoom, like a browser's zoom badge.
struct TaskWindowZoomIndicator: View {
    let text: String
    let isActualSize: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            if isActualSize {
                Text("Actual Size")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zoom \(text)")
        .accessibilityIdentifier("zoomIndicator")
    }
}
