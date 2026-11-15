import SwiftUI
import AppKit
import os

// The calendar is an endless, continuously scrolling list of weeks. `offset`
// is measured in weeks relative to the week containing the first day of the
// month PopCal was opened on; the row at the top of the grid is `floor(offset)`.
// Two-finger trackpad scrolling, mouse wheels, click-dragging and the chevron
// buttons all just move `offset`. When the gesture ends it snaps to a whole week.

struct CalendarView: View {
    @StateObject private var prefs = AppPreferences.shared
    @State private var anchorMonth: Date
    @State private var offset: Double = 0
    @State private var dragStartOffset: Double?
    @State private var pendingSnap: DispatchWorkItem?
    /// The day chosen with the arrow keys; nil until the keyboard is used.
    @State private var selectedDate: Date?

    /// Pins "now" (for screenshots and tests); nil means the real current time.
    private let fixedNow: Date?
    private var now: Date { fixedNow ?? Date() }

    init(now: Date? = nil) {
        fixedNow = now
        _anchorMonth = State(initialValue: (now ?? Date()).startOfMonth())
    }

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

                    WeekGrid(offset: offset, geometry: geo, today: now, selectedDate: selectedDate, weekendColumns: weekend)
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
        .background(EventReceiver(onScroll: handleScroll, onKeyDown: handleKeyDown))
        .onReceive(NotificationCenter.default.publisher(for: .popCalWillShow)) { _ in
            resetToToday()
        }
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
                Button("Today") { goToToday() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.accentColor)
            } else {
                Text(Self.todayFormatter.string(from: now))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Navigation

    /// Chevron buttons and n/p: scroll so the first week of the next/previous
    /// month is at the top. A keyboard selection moves by the same number of months.
    func navigate(months: Int) {
        guard let target = calendar.date(byAdding: .month, value: months, to: focusedMonth) else { return }
        if let selected = selectedDate {
            selectedDate = calendar.date(byAdding: .month, value: months, to: selected)
        }
        scroll(toMonth: target)
    }

    /// Each time the popover opens, show the current month with nothing selected.
    func resetToToday() {
        cancelSnap()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            anchorMonth = now.startOfMonth()
            offset = 0
            selectedDate = nil
            dragStartOffset = nil
        }
    }

    func goToToday() {
        if selectedDate != nil {
            selectedDate = calendar.startOfDay(for: now)
        }
        scroll(toMonth: now)
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

    // MARK: - Keyboard

    /// Returns true if the key was handled.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Leave ⌘/⌃/⌥ shortcuts to the system.
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }

        switch event.keyCode {
        case 123: moveSelection(byDays: -1)          // ←
        case 124: moveSelection(byDays: 1)           // →
        case 125: moveSelection(byDays: 7)           // ↓
        case 126: moveSelection(byDays: -7)          // ↑
        case 36, 76:                                 // Return, keypad Enter
            CalendarOpener.open(selectedDate ?? now)
        case 53:                                     // Esc
            AppDelegate.shared?.closePopover()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "t":
                selectedDate = calendar.startOfDay(for: now)
                scroll(toMonth: now)
            case "n": navigate(months: 1)
            case "p": navigate(months: -1)
            default: return false
            }
        }
        return true
    }

    /// The first arrow key press selects today (or the 1st of the month on
    /// screen); later presses move the selection.
    private func moveSelection(byDays days: Int) {
        let next: Date
        if let selected = selectedDate {
            next = calendar.date(byAdding: .day, value: days, to: selected) ?? selected
        } else if calendar.isDate(now, equalTo: focusedMonth, toGranularity: .month) {
            next = calendar.startOfDay(for: now)
        } else {
            next = focusedMonth
        }
        selectedDate = next
        reveal(next)
    }

    /// Scrolls the least amount needed to bring `date`'s week into view.
    private func reveal(_ date: Date) {
        let row = Double(geometry.row(containing: date))
        let lastVisible = Double(Self.visibleRows - 1)
        var target = offset.rounded()
        if row < target {
            target = row
        } else if row > target + lastVisible {
            target = row - lastVisible
        }
        guard target != offset else { return }
        cancelSnap()
        withAnimation(.easeInOut(duration: 0.2)) {
            offset = target
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
        calendar.isDate(focusedMonth, equalTo: now, toGranularity: .month)
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
    let today: Date
    let selectedDate: Date?
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
                            isToday: geometry.calendar.isDate(date, inSameDayAs: today),
                            isSelected: selectedDate.map { geometry.calendar.isDate(date, inSameDayAs: $0) } ?? false,
                            calendar: geometry.calendar
                        )
                        .onTapGesture { CalendarOpener.open(date) }
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
    let isToday: Bool
    var isSelected: Bool = false
    let calendar: Calendar

    @State private var isHovered = false

    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
            } else if isHovered || isSelected {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 28, height: 28)
            }

            if isSelected {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .frame(width: isToday ? 32 : 28, height: isToday ? 32 : 28)
            }

            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 12, weight: isToday ? .bold : (isInFocusedMonth ? .regular : .light), design: .rounded))
                .foregroundColor(textColor)
                .animation(.easeInOut(duration: 0.2), value: isInFocusedMonth)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CalendarView.rowHeight)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .help(Self.helpFormatter.string(from: date))
    }

    private static let helpFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .full
        return fmt
    }()

    var textColor: Color {
        if isToday { return .white }
        if !isInFocusedMonth { return .secondary.opacity(0.5) }
        if isWeekend { return .secondary }
        return .primary
    }
}

// MARK: - Opening a day

/// Opens the user's calendar (Calendar.app or Google Calendar, per Settings) on a given day.
enum CalendarOpener {
    /// Year/month/day in the Gregorian calendar, which both Google Calendar
    /// URLs and AppleScript dates use, whatever the user's system calendar is.
    static func gregorianComponents(of date: Date) -> (year: Int, month: Int, day: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    static func googleCalendarURL(for date: Date) -> URL {
        let (y, m, d) = gregorianComponents(of: date)
        return URL(string: "https://calendar.google.com/calendar/r/day/\(y)/\(m)/\(d)")!
    }

    /// AppleScript that shows `date` in Calendar's day view. The date is built
    /// field by field so it doesn't depend on the locale's date format.
    static func calendarAppScript(for date: Date) -> String {
        let (y, m, d) = gregorianComponents(of: date)
        return """
        set theDate to current date
        set day of theDate to 1
        set year of theDate to \(y)
        set month of theDate to \(m)
        set day of theDate to \(d)
        set time of theDate to 12 * hours
        tell application "Calendar"
            if it is not running then
                launch
                delay 1
            end if
            activate
            switch view to day view
            view calendar at theDate
        end tell
        """
    }

    private static let log = Logger(subsystem: "com.popcal.app", category: "CalendarOpener")

    static func open(_ date: Date) {
        AppDelegate.shared?.closePopover()

        switch AppPreferences.shared.calendarDestination {
        case .google:
            NSWorkspace.shared.open(googleCalendarURL(for: date))
        case .system:
            runCalendarScript(calendarAppScript(for: date))
        }
    }

    /// Runs the script with osascript so it never blocks PopCal (the first run
    /// waits on the automation permission prompt) and errors are reported.
    private static func runCalendarScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        process.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            log.error("Opening Calendar failed (status \(process.terminationStatus)): \(message, privacy: .public)")
            DispatchQueue.main.async {
                if message.contains("-1743") {
                    showAutomationPermissionAlert()
                } else {
                    openCalendarApp()
                }
            }
        }
        do {
            try process.run()
        } catch {
            log.error("Couldn't run osascript: \(error.localizedDescription, privacy: .public)")
            openCalendarApp()
        }
    }

    /// Error -1743: macOS refused to let PopCal control Calendar.
    private static func showAutomationPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "PopCal isn't allowed to control Calendar"
        alert.informativeText = """
        To open Calendar on the day you click, turn on Calendar under PopCal in \
        System Settings → Privacy & Security → Automation.

        If PopCal isn't listed there, reset its permission in Terminal, then click a day again:
        tccutil reset AppleEvents com.popcal.app
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Open Calendar")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        default:
            openCalendarApp()
        }
    }

    private static func openCalendarApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

// MARK: - Scroll wheel and keyboard events

/// Two-finger trackpad scrolls arrive as scroll-wheel events, which SwiftUI
/// gestures don't see on macOS 13, and key handling (`onKeyPress`) needs
/// macOS 14. This view watches its window for scroll events over its bounds
/// and for key presses, and forwards them. It never takes mouse clicks.
struct EventReceiver: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void
    /// Returns true if the key was handled (and should not go further).
    var onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onScroll = onScroll
        view.onKeyDown = onKeyDown
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        var onKeyDown: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                if event.type == .keyDown {
                    return self.onKeyDown?(event) == true ? nil : event
                }
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
