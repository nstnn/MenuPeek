import Foundation

// The Day/Week grid's pointer drags as plain values: what kind of drag it is,
// where it started and where the pointer is now, in grid coordinates (the top
// left of the first day column at the 00:00 line). The view draws the preview
// from `result(metrics:)` and saves the same result on release, so what the
// user saw is what is saved. No SwiftUI or AppKit: tests drive every path.

/// One drag on the time grid, from mouse-down to release or Escape.
struct ScheduleDragSession: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Drawing a new block on empty space in `day`'s column.
        case create(day: GregorianDay)
        /// Dragging the lower edge of a saved block.
        case resize(ScheduleBlock)
    }

    /// Movement below this distance (in points) is a click, not a drag.
    static let minimumDistance: CGFloat = 4

    let kind: Kind
    /// Where the mouse went down.
    let anchor: CGPoint
    /// The pointer now. Only `update(to:)` changes it.
    private(set) var current: CGPoint
    /// Set once the pointer has travelled `minimumDistance` from the anchor;
    /// it stays set if the pointer returns, so a drag never turns back into a click.
    private(set) var isDragging = false

    private init(kind: Kind, anchor: CGPoint) {
        self.kind = kind
        self.anchor = anchor
        current = anchor
    }

    /// A drag that starts on empty grid space: the column under `point` picks
    /// the day. Nil above or below the day or with no columns, like a click.
    static func create(at point: CGPoint, columnWidth: CGFloat, days: [GregorianDay],
                       metrics: ScheduleGridMetrics) -> ScheduleDragSession? {
        guard point.y.isFinite, point.y >= 0, point.y < metrics.dayHeight,
              let column = ScheduleGridGeometry.columnIndex(atX: point.x, columnWidth: columnWidth,
                                                            columnCount: days.count) else { return nil }
        return ScheduleDragSession(kind: .create(day: days[column]), anchor: point)
    }

    /// A drag that starts on `block`'s lower edge at `point`.
    static func resize(_ block: ScheduleBlock, at point: CGPoint) -> ScheduleDragSession? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return ScheduleDragSession(kind: .resize(block), anchor: point)
    }

    mutating func update(to point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        current = point
        if !isDragging, hypot(point.x - anchor.x, point.y - anchor.y) >= Self.minimumDistance {
            isDragging = true
        }
    }

    /// The block this drag would produce now, from the same planners the
    /// release saves with. Nil while the pointer has not moved far enough.
    func result(metrics: ScheduleGridMetrics) -> ScheduleDragResult? {
        guard isDragging else { return nil }
        switch kind {
        case let .create(day):
            guard let span = ScheduleDragPlanner.create(anchorMinute: metrics.minute(atOffset: anchor.y),
                                                        currentMinute: metrics.minute(atOffset: current.y))
            else { return nil }
            return .create(day: day, span: span)
        case let .resize(block):
            // The edge follows the pointer's travel, so grabbing a few points
            // above the edge does not make the block jump.
            let travel = metrics.minute(atOffset: current.y) - metrics.minute(atOffset: anchor.y)
            guard let content = ScheduleDragPlanner.resize(block, endMinute: Double(block.endMinute) + travel)
            else { return nil }
            return .resize(block: block, to: content)
        }
    }

    /// The block being resized, so the grid can dim it under the preview.
    var resizingBlockID: UUID? {
        if case let .resize(block) = kind { block.id } else { nil }
    }
}

/// What a drag produces on release.
enum ScheduleDragResult: Equatable, Sendable {
    /// Open the editor on this day and span, with the title focused.
    case create(day: GregorianDay, span: ScheduleTimeSpan)
    /// Save these values for `block` (only its end differs).
    case resize(block: ScheduleBlock, to: ScheduleBlockContent)

    var day: GregorianDay {
        switch self {
        case let .create(day, _): day
        case let .resize(_, content): content.day
        }
    }

    var startMinute: Int {
        switch self {
        case let .create(_, span): span.startMinute
        case let .resize(_, content): content.startMinute
        }
    }

    var endMinute: Int {
        switch self {
        case let .create(_, span): span.endMinute
        case let .resize(_, content): content.endMinute
        }
    }

    /// "10:00–11:30", drawn inside the preview.
    var timeText: String {
        "\(ScheduleBlockContent.clockText(minute: startMinute))–\(ScheduleBlockContent.clockText(minute: endMinute))"
    }

    /// False for a resize that ends where the block already ends: nothing to save.
    var changesSavedBlock: Bool {
        guard case let .resize(block, content) = self else { return true }
        return content.endMinute != block.endMinute
    }
}

/// How fast the grid scrolls while a drag holds the pointer near or past its
/// top or bottom edge.
enum ScheduleDragAutoScroll {
    /// The band at each edge where scrolling starts.
    static let edgeBand: CGFloat = 40
    /// Points per tick at the edge and beyond it (ticks run at 30 Hz).
    static let maximumStep: CGFloat = 12

    /// Negative scrolls up, positive down, zero inside the middle of the
    /// viewport. `y` is measured from the viewport's top; a pointer above or
    /// below the viewport scrolls at full speed.
    static func step(pointerY y: CGFloat, viewportHeight height: CGFloat) -> CGFloat {
        guard y.isFinite, height.isFinite, height > 0 else { return 0 }
        let band = min(edgeBand, height / 2)
        if y < band {
            return -maximumStep * min(1, (band - y) / band)
        }
        if y > height - band {
            return maximumStep * min(1, (y - (height - band)) / band)
        }
        return 0
    }
}

extension ScheduleBlockDraft {
    /// A new block on `day` with exactly the span a drag drew.
    init(newOn day: GregorianDay, span: ScheduleTimeSpan) {
        self.init(newOn: day, startMinute: span.startMinute)
        setEnd(span.endMinute)
    }
}

extension ScheduleEditorRequest {
    /// The editor for a block drawn by dragging on empty grid space.
    static func drawn(day: GregorianDay, span: ScheduleTimeSpan) -> Self {
        Self(origin: .slot(day: day, startMinute: span.startMinute),
             draft: ScheduleBlockDraft(newOn: day, span: span))
    }
}
