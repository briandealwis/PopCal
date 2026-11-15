import SwiftUI
import AppKit

// The calendar is an endless, continuously scrolling list of weeks. `offset`
// is measured in weeks relative to the week containing the first day of the
// month PopCal was opened on; the row at the top of the grid is `floor(offset)`.
// Two-finger trackpad scrolling, mouse wheels, click-dragging and the chevron
// buttons all just move `offset`. When the gesture ends it snaps to a whole week.

struct CalendarView: View {
    @StateObject private var prefs = AppPreferences.shared
    @State private var anchorMonth: Date = Date().startOfMonth()
    @State private var offset: Double = 0
    @State private var dragStartOffset: Double?
    @State private var pendingSnap: DispatchWorkItem?

    private let today = Date()

    static let rowHeight: CGFloat = 32
    static let visibleRows = 6

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = prefs.weekStartsOnMonday ? 2 : 1
        return cal
    }

    private var geometry: CalendarGeometry {
        CalendarGeometry(calendar: calendar, referenceMonth: anchorMonth)
    }

    /// The month named in the header: the one in the middle of the visible weeks.
    private var focusedMonth: Date {
        geometry.focusedMonth(offset: offset, visibleRows: Self.visibleRows)
    }

    var body: some View {
        let geo = geometry
        let weekend = geo.weekendColumns

        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider().opacity(0.4)

                VStack(spacing: 4) {
                    weekdayRow(weekend: weekend)
                        .padding(.top, 6)

                    WeekGrid(offset: offset, geometry: geo, weekendColumns: weekend)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                }
                .padding(.bottom, 4)
                .background(WeekendBands(weekendColumns: weekend))
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)

                Divider().opacity(0.4)

                footerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 300, height: 320)
        .background(ScrollWheelReceiver(onScroll: handleScroll))
    }

    // MARK: - Header

    var headerView: some View {
        HStack {
            Button(action: { navigate(months: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(Self.monthFormatter.string(from: focusedMonth))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(Self.yearFormatter.string(from: focusedMonth))
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { navigate(months: 1) }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Weekday Row

    func weekdayRow(weekend: [Bool]) -> some View {
        let symbols = orderedWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                Text(symbols[column])
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(weekend[column] ? .secondary.opacity(0.7) : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Footer

    var footerView: some View {
        HStack {
            if !isShowingCurrentMonth {
                Button("Today") { scroll(toMonth: Date()) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.accentColor)
            } else {
                Text(Self.todayFormatter.string(from: today))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Navigation

    /// Chevron buttons: scroll so the first week of the next/previous month is at the top.
    func navigate(months: Int) {
        guard let target = calendar.date(byAdding: .month, value: months, to: focusedMonth) else { return }
        scroll(toMonth: target)
    }

    func scroll(toMonth month: Date) {
        cancelSnap()
        let target = Double(geometry.row(forMonthOf: month))
        withAnimation(.easeInOut(duration: 0.3)) {
            offset = target
        }
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragStartOffset == nil {
                    cancelSnap()
                    dragStartOffset = offset
                }
                offset = (dragStartOffset ?? offset) - Double(value.translation.height / Self.rowHeight)
            }
            .onEnded { value in
                let start = dragStartOffset ?? offset
                dragStartOffset = nil
                let predicted = start - Double(value.predictedEndTranslation.height / Self.rowHeight)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    offset = predicted.rounded()
                }
            }
    }

    // MARK: - Scroll wheel / trackpad

    private func handleScroll(_ event: NSEvent) {
        guard dragStartOffset == nil else { return }
        let dy = Double(event.scrollingDeltaY)

        if event.hasPreciseScrollingDeltas {
            // Trackpad or Magic Mouse: follow the fingers, including momentum.
            if event.phase.contains(.began) || event.phase.contains(.mayBegin)
                || event.momentumPhase.contains(.began) {
                cancelSnap()
            }

            if dy != 0 {
                offset -= dy / Double(Self.rowHeight)
            }

            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                snap()
            } else if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                // Fingers lifted; momentum events may follow, so wait briefly before snapping.
                scheduleSnap()
            } else if event.phase.isEmpty && event.momentumPhase.isEmpty {
                // Precise device that reports no phases.
                scheduleSnap()
            }
        } else {
            // Classic mouse wheel: one notch moves one week.
            guard dy != 0 else { return }
            cancelSnap()
            withAnimation(.easeOut(duration: 0.18)) {
                offset = offset.rounded() + (dy > 0 ? -1 : 1)
            }
        }
    }

    private func snap() {
        cancelSnap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            offset = offset.rounded()
        }
    }

    private func scheduleSnap() {
        cancelSnap()
        let work = DispatchWorkItem { snap() }
        pendingSnap = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func cancelSnap() {
        pendingSnap?.cancel()
        pendingSnap = nil
    }

    // MARK: - Computed

    var isShowingCurrentMonth: Bool {
        calendar.isDate(focusedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// Very short weekday symbols ("S", "M", …), rotated to the configured first weekday.
    var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private static let monthFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("MMMM")
        return fmt
    }()

    private static let yearFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("yyyy")
        return fmt
    }()

    private static let todayFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.setLocalizedDateFormatFromTemplate("EEEE MMMM d")
        return fmt
    }()
}

// MARK: - CalendarGeometry

/// Maps between week rows and dates. Row 0 is the week containing the first
/// day of `referenceMonth`; negative rows are earlier weeks.
struct CalendarGeometry {
    let calendar: Calendar
    let anchor: Date

    init(calendar: Calendar, referenceMonth: Date) {
        self.calendar = calendar
        let firstOfMonth = calendar.dateInterval(of: .month, for: referenceMonth)?.start
            ?? calendar.startOfDay(for: referenceMonth)
        anchor = calendar.dateInterval(of: .weekOfYear, for: firstOfMonth)?.start ?? firstOfMonth
    }

    func date(row: Int, column: Int) -> Date {
        calendar.date(byAdding: .day, value: row * 7 + column, to: anchor)!
    }

    func row(containing date: Date) -> Int {
        let days = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day ?? 0
        return Int((Double(days) / 7).rounded(.down))
    }

    /// The row holding the first day of the month that contains `date`.
    func row(forMonthOf date: Date) -> Int {
        let first = calendar.dateInterval(of: .month, for: date)?.start ?? date
        return row(containing: first)
    }

    /// The month of the mid-week day in the middle row of the visible weeks.
    func focusedMonth(offset: Double, visibleRows: Int) -> Date {
        let middleRow = Int((offset + Double(visibleRows) / 2).rounded(.down))
        let day = date(row: middleRow, column: 3)
        return calendar.dateInterval(of: .month, for: day)?.start ?? day
    }

    /// Which of the seven columns fall on the weekend (locale-aware).
    var weekendColumns: [Bool] {
        (0..<7).map { calendar.isDateInWeekend(date(row: 0, column: $0)) }
    }
}

// MARK: - WeekGrid

/// Draws the weeks visible at a (possibly fractional) offset. It is
/// `Animatable`, so animating `offset` scrolls smoothly over every row in between.
struct WeekGrid: View, Animatable {
    var offset: Double
    let geometry: CalendarGeometry
    let weekendColumns: [Bool]

    var animatableData: Double {
        get { offset }
        set { offset = newValue }
    }

    var body: some View {
        let rowHeight = CalendarView.rowHeight
        let visibleRows = CalendarView.visibleRows
        let firstRow = Int(offset.rounded(.down))
        let fraction = CGFloat(offset - Double(firstRow))
        let focusedMonth = geometry.focusedMonth(offset: offset, visibleRows: visibleRows)

        ZStack(alignment: .top) {
            ForEach(firstRow...(firstRow + visibleRows), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let date = geometry.date(row: row, column: column)
                        DayCell(
                            date: date,
                            isInFocusedMonth: geometry.calendar.isDate(date, equalTo: focusedMonth, toGranularity: .month),
                            isWeekend: weekendColumns[column],
                            calendar: geometry.calendar
                        )
                    }
                }
                .frame(height: rowHeight)
                .offset(y: (CGFloat(row - firstRow) - fraction) * rowHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight * CGFloat(visibleRows), alignment: .top)
        .clipped()
    }
}

// MARK: - Weekend bands

/// Subtle grey column bands behind the weekend columns. Adjacent weekend
/// columns (e.g. Sat+Sun with a Monday week start) share one band.
struct WeekendBands: View {
    let weekendColumns: [Bool]

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = proxy.size.width / 7
            ForEach(runs) { run in
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
                    .frame(width: columnWidth * CGFloat(run.length), height: proxy.size.height)
                    .offset(x: columnWidth * CGFloat(run.start))
            }
        }
    }

    private struct Run: Identifiable {
        let start: Int
        let length: Int
        var id: Int { start }
    }

    private var runs: [Run] {
        var result: [Run] = []
        var column = 0
        while column < weekendColumns.count {
            if weekendColumns[column] {
                let start = column
                while column < weekendColumns.count && weekendColumns[column] { column += 1 }
                result.append(Run(start: start, length: column - start))
            } else {
                column += 1
            }
        }
        return result
    }
}

// MARK: - CalendarDay model

struct CalendarDay: Identifiable {
    let id = UUID()
    let date: Date
    let isCurrentMonth: Bool
}

// MARK: - DayCell

struct DayCell: View {
    let date: Date
    let isInFocusedMonth: Bool
    let isWeekend: Bool
    let calendar: Calendar

    var isToday: Bool { calendar.isDateInToday(date) }

    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : (isInFocusedMonth ? .regular : .light), design: .rounded))
                .foregroundColor(textColor)
                .animation(.easeInOut(duration: 0.2), value: isInFocusedMonth)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CalendarView.rowHeight)
        .contentShape(Rectangle())
    }

    var textColor: Color {
        if isToday { return .white }
        if !isInFocusedMonth { return .secondary.opacity(0.5) }
        if isWeekend { return .secondary }
        return .primary
    }
}

// MARK: - Scroll wheel events

/// Two-finger trackpad scrolls arrive as scroll-wheel events, which SwiftUI
/// gestures don't see on macOS 13. This view watches for scroll events over
/// its bounds in its window and forwards them. It never takes mouse clicks.
struct ScrollWheelReceiver: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                self.onScroll?(event)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit { removeMonitor() }
    }
}

// MARK: - Date helpers

extension Date {
    func startOfMonth() -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: self))!
    }
}
