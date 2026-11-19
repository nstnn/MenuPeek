import Foundation

// Pure Calendar time-grid math: minutes ↔ vertical offsets, 15-minute
// snapping, side-by-side layout for overlapping blocks, and the planners the
// drag gestures call for both their live preview and their final result.
// No SwiftUI: views pass sizes in and draw what comes back.

/// The vertical scale of a Day or Week time grid. Offsets are measured from
/// the top of the 00:00 line; zoom changes only `hourHeight`.
struct ScheduleGridMetrics: Equatable, Sendable {
    let hourHeight: CGFloat

    init(hourHeight: CGFloat) {
        precondition(hourHeight.isFinite && hourHeight > 0, "hour height must be positive")
        self.hourHeight = hourHeight
    }

    var minuteHeight: CGFloat { hourHeight / 60 }
    /// Height of the whole 24-hour grid.
    var dayHeight: CGFloat { offset(forMinute: ScheduleBlockContent.minutesPerDay) }

    func offset(forMinute minute: Int) -> CGFloat { offset(forMinute: Double(minute)) }

    /// Accepts fractional minutes for the current-time line.
    /// Multiplies before dividing, so whole minutes land on exact offsets.
    func offset(forMinute minute: Double) -> CGFloat { CGFloat(minute) * hourHeight / 60 }

    /// The raw minute under a vertical offset: neither snapped nor clamped, so
    /// a drag above or below the grid reads as a minute outside 0...1440.
    func minute(atOffset offset: CGFloat) -> Double { Double(offset * 60 / hourHeight) }

    /// The block's rectangle inside one day column of `columnWidth`, using the
    /// placement's column so overlapping blocks sit side by side.
    func rect(for placement: ScheduleBlockPlacement, columnWidth: CGFloat) -> CGRect {
        let width = columnWidth / CGFloat(placement.columnCount)
        let top = offset(forMinute: placement.block.startMinute)
        return CGRect(x: width * CGFloat(placement.column), y: top,
                      width: width, height: offset(forMinute: placement.block.endMinute) - top)
    }
}

/// Snapping, clamping and column hit-testing shared by the grid and the planners.
enum ScheduleGridGeometry {
    static let slotMinutes = ScheduleBlockContent.slotMinutes
    static let minutesPerDay = ScheduleBlockContent.minutesPerDay

    /// The 15-minute line nearest to `raw` (a half-slot rounds later), clamped
    /// to 00:00...24:00. Nil for a non-finite input.
    static func snappedMinute(_ raw: Double) -> Int? {
        guard raw.isFinite else { return nil }
        let clamped = min(max(raw, 0), Double(minutesPerDay))
        let slots = (clamped / Double(slotMinutes)).rounded(.toNearestOrAwayFromZero)
        return Int(slots) * slotMinutes
    }

    /// Start of the 15-minute slot containing `raw`, clamped to 00:00...23:45,
    /// for a plain click on empty grid space. Nil for a non-finite input.
    static func slotStartMinute(containing raw: Double) -> Int? {
        guard raw.isFinite else { return nil }
        let clamped = min(max(raw, 0), Double(ScheduleBlockContent.latestStartMinute))
        return Int((clamped / Double(slotMinutes)).rounded(.down)) * slotMinutes
    }

    /// The start that keeps a block of `durationMinutes` inside the day:
    /// at least 00:00 and ending no later than 24:00.
    static func clampedStart(_ start: Int, durationMinutes: Int) -> Int {
        min(max(start, 0), max(minutesPerDay - durationMinutes, 0))
    }

    /// The day column under a horizontal offset, clamped to the visible
    /// columns so a drag past either edge stays on the first or last day.
    /// Nil when there is no column or the input is not finite.
    static func columnIndex(atX x: CGFloat, columnWidth: CGFloat, columnCount: Int) -> Int? {
        guard columnCount > 0, columnWidth > 0, x.isFinite, columnWidth.isFinite else { return nil }
        let index = (x / columnWidth).rounded(.down)
        return Int(min(max(index, 0), CGFloat(columnCount - 1)))
    }
}

// MARK: - Overlap layout

/// Where one block sits among the blocks it overlaps on its day: column
/// `column` of `columnCount` equal columns. A block that overlaps nothing has
/// column 0 of 1 (full width).
struct ScheduleBlockPlacement: Identifiable, Equatable, Sendable {
    let block: ScheduleBlock
    let column: Int
    let columnCount: Int

    var id: UUID { block.id }
    /// Leading edge as a fraction of the day column's width.
    var leadingFraction: Double { Double(column) / Double(columnCount) }
    var widthFraction: Double { 1 / Double(columnCount) }
}

enum ScheduleOverlapLayout {
    /// Lays out each day independently. Within a day, blocks are swept in
    /// start order (ties: creation instant, then ID text), so the result never
    /// depends on input order. Connected overlaps form a group that shares one
    /// column count; each block takes the leftmost column that is free at its
    /// start. Blocks that only touch (one ends as the next starts) do not
    /// overlap and keep full width.
    ///
    /// Returns one placement per block, in day then sweep order.
    static func placements(for blocks: [ScheduleBlock]) -> [ScheduleBlockPlacement] {
        let sorted = blocks.sorted(by: isLaidOutBefore)
        var result: [ScheduleBlockPlacement] = []
        result.reserveCapacity(sorted.count)

        var group: [(block: ScheduleBlock, column: Int)] = []
        var columnEnds: [Int] = []
        var groupEnd = 0

        func closeGroup() {
            let count = columnEnds.count
            result += group.map { ScheduleBlockPlacement(block: $0.block, column: $0.column, columnCount: count) }
            group.removeAll(keepingCapacity: true)
            columnEnds.removeAll(keepingCapacity: true)
        }

        for block in sorted {
            if let last = group.last?.block, last.day != block.day || block.startMinute >= groupEnd {
                closeGroup()
            }
            if group.isEmpty { groupEnd = block.endMinute }
            let column = columnEnds.firstIndex { $0 <= block.startMinute } ?? columnEnds.count
            if column == columnEnds.count {
                columnEnds.append(block.endMinute)
            } else {
                columnEnds[column] = block.endMinute
            }
            group.append((block, column))
            groupEnd = max(groupEnd, block.endMinute)
        }
        closeGroup()
        return result
    }

    private static func isLaidOutBefore(_ lhs: ScheduleBlock, _ rhs: ScheduleBlock) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        if lhs.startMinute != rhs.startMinute { return lhs.startMinute < rhs.startMinute }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

// MARK: - Drag planners

/// A valid start and end on one day (see `ScheduleBlockContent.validateTimes`),
/// before a title exists. Only the create planner produces one.
struct ScheduleTimeSpan: Equatable, Sendable {
    let startMinute: Int
    let endMinute: Int

    /// Nil unless the times pass every block time rule.
    init?(startMinute: Int, endMinute: Int) {
        guard (try? ScheduleBlockContent.validateTimes(startMinute: startMinute,
                                                       endMinute: endMinute)) != nil else { return nil }
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    var durationMinutes: Int { endMinute - startMinute }
}

/// Pure planners for the three drag gestures. Views call them for every
/// preview frame and again on release, so the preview and the saved block
/// always agree. Inputs are raw minutes from `ScheduleGridMetrics.minute(atOffset:)`.
/// A planner returns nil only for a gesture that cannot yield a valid block
/// (a non-finite input), so a view never holds an invalid block to save.
enum ScheduleDragPlanner {
    /// Drag on empty grid space. Both points snap to the nearest 15-minute
    /// line within the day; the block spans from the earlier to the later, so
    /// dragging up or down over the same span gives the same block. A span
    /// shorter than one slot grows to 15 minutes (ending at 24:00 at the
    /// bottom of the day).
    static func create(anchorMinute: Double, currentMinute: Double) -> ScheduleTimeSpan? {
        guard let anchor = ScheduleGridGeometry.snappedMinute(anchorMinute),
              let current = ScheduleGridGeometry.snappedMinute(currentMinute) else { return nil }
        let slot = ScheduleGridGeometry.slotMinutes
        var start = min(anchor, current)
        var end = max(anchor, current)
        if end - start < slot {
            start = min(start, ScheduleBlockContent.latestStartMinute)
            end = start + slot
        }
        return ScheduleTimeSpan(startMinute: start, endMinute: end)
    }

    /// Drag of a block's lower edge. The end snaps to the nearest 15-minute
    /// line and stays between start + 15 minutes and 24:00, so dragging above
    /// the start leaves the 15-minute minimum, never a reversed block. Title,
    /// day and start are kept.
    static func resize(_ block: ScheduleBlock, endMinute rawEnd: Double) -> ScheduleBlockContent? {
        guard let snapped = ScheduleGridGeometry.snappedMinute(rawEnd) else { return nil }
        let end = max(snapped, block.startMinute + ScheduleGridGeometry.slotMinutes)
        return try? ScheduleBlockContent(title: block.title, day: block.day,
                                         startMinute: block.startMinute, endMinute: end)
    }

    /// Drag of a block's body to `day` (the column under the pointer; the
    /// view clamps it to the visible days). `startMinute` is the raw minute of
    /// the block's top edge, i.e. the pointer minus the grab offset inside the
    /// block. The start snaps to the nearest 15-minute line and is clamped so
    /// the block stays inside the day with its duration unchanged.
    static func move(_ block: ScheduleBlock, to day: GregorianDay,
                     startMinute rawStart: Double) -> ScheduleBlockContent? {
        guard let snapped = ScheduleGridGeometry.snappedMinute(rawStart) else { return nil }
        let duration = block.durationMinutes
        let start = ScheduleGridGeometry.clampedStart(snapped, durationMinutes: duration)
        return try? ScheduleBlockContent(title: block.title, day: day,
                                         startMinute: start, endMinute: start + duration)
    }
}

// MARK: - Slot hit-testing

/// The empty-grid click target. A plain click opens the editor on the slot
/// under the pointer; a drag from the same point draws a block instead.
enum ScheduleSlotHitTest {
    /// The day and slot start under `point`, measured from the top-left of the
    /// first day column at the 00:00 line. Nil above or below the day, or with
    /// no columns.
    static func slot(at point: CGPoint, columnWidth: CGFloat, days: [GregorianDay],
                     metrics: ScheduleGridMetrics) -> (day: GregorianDay, startMinute: Int)? {
        guard point.y >= 0, point.y < metrics.dayHeight,
              let column = ScheduleGridGeometry.columnIndex(atX: point.x, columnWidth: columnWidth,
                                                            columnCount: days.count),
              let minute = ScheduleGridGeometry.slotStartMinute(containing: metrics.minute(atOffset: point.y))
        else { return nil }
        return (days[column], minute)
    }
}
