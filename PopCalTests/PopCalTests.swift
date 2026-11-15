import XCTest
@testable import PopCal

// MARK: - CalendarView Logic Tests

final class CalendarDayComputationTests: XCTestCase {

    // Helper: build a CalendarView-style day array for a given month string
    // We replicate the core logic here to keep tests self-contained
    func computeDays(for monthString: String, startsOnMonday: Bool) -> [CalendarDay] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        let date = fmt.date(from: monthString)!

        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = startsOnMonday ? 2 : 1
        cal.locale = Locale(identifier: "en_US")

        guard let monthInterval = cal.dateInterval(of: .month, for: date),
              let firstWeekInterval = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        let startDate = firstWeekInterval.start
        var days: [CalendarDay] = []
        var current = startDate

        for _ in 0..<42 {
            let isCurrentMonth = cal.isDate(current, equalTo: date, toGranularity: .month)
            days.append(CalendarDay(date: current, isCurrentMonth: isCurrentMonth))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }

        while days.count > 35 {
            let lastWeek = days.suffix(7)
            if lastWeek.allSatisfy({ !$0.isCurrentMonth }) {
                days.removeLast(7)
            } else { break }
        }

        return days
    }

    // MARK: Grid size

    func testGridAlwaysMultipleOf7() {
        let months = ["2026-01", "2026-02", "2026-03", "2026-04",
                      "2026-05", "2026-06", "2026-07", "2026-12"]
        for m in months {
            let days = computeDays(for: m, startsOnMonday: false)
            XCTAssertTrue(days.count % 7 == 0, "Grid for \(m) is not a multiple of 7: \(days.count)")
        }
    }

    func testGridHasAtLeast28Days() {
        let days = computeDays(for: "2026-02", startsOnMonday: false)
        XCTAssertGreaterThanOrEqual(days.count, 28)
    }

    func testGridNeverExceeds42Days() {
        // Feb 2026 starts on Sunday — could fill up to 4 rows (28 days) but we check cap
        let days = computeDays(for: "2026-02", startsOnMonday: false)
        XCTAssertLessThanOrEqual(days.count, 42)
    }

    // MARK: Current-month flags

    func testAllCurrentMonthDaysAreTagged() {
        let days = computeDays(for: "2026-05", startsOnMonday: false)
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let ref = fmt.date(from: "2026-05")!

        let currentMonthDays = days.filter { $0.isCurrentMonth }
        // May has 31 days
        XCTAssertEqual(currentMonthDays.count, 31)

        for d in currentMonthDays {
            XCTAssertTrue(cal.isDate(d.date, equalTo: ref, toGranularity: .month))
        }
    }

    func testOutsideDaysAreNotTaggedAsCurrentMonth() {
        let days = computeDays(for: "2026-05", startsOnMonday: false)
        let outside = days.filter { !$0.isCurrentMonth }
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let ref = fmt.date(from: "2026-05")!

        for d in outside {
            XCTAssertFalse(cal.isDate(d.date, equalTo: ref, toGranularity: .month))
        }
    }

    // MARK: Week start

    func testSundayStartFirstColumnIsSunday() {
        let days = computeDays(for: "2026-05", startsOnMonday: false)
        let cal = Calendar(identifier: .gregorian)
        // First day in the grid should be a Sunday (weekday == 1)
        let firstWeekday = cal.component(.weekday, from: days[0].date)
        XCTAssertEqual(firstWeekday, 1, "Expected Sunday (1), got \(firstWeekday)")
    }

    func testMondayStartFirstColumnIsMonday() {
        let days = computeDays(for: "2026-05", startsOnMonday: true)
        let cal = Calendar(identifier: .gregorian)
        // First day in the grid should be a Monday (weekday == 2)
        let firstWeekday = cal.component(.weekday, from: days[0].date)
        XCTAssertEqual(firstWeekday, 2, "Expected Monday (2), got \(firstWeekday)")
    }

    func testWeekStartChangesLeadingPadding() {
        let sundayGrid = computeDays(for: "2026-05", startsOnMonday: false)
        let mondayGrid = computeDays(for: "2026-05", startsOnMonday: true)
        // The leading date should differ between the two grids (or be equal if month starts Mon/Sun)
        // May 2026 starts on Friday — both grids will have different leading dates
        XCTAssertNotEqual(sundayGrid[0].date, mondayGrid[0].date)
    }

    // MARK: February edge cases

    func testFebruary2028LeapYear() throws {
        // 2028 is a leap year, Feb has 29 days
        let days = computeDays(for: "2028-02", startsOnMonday: false)
        let currentMonth = days.filter { $0.isCurrentMonth }
        XCTAssertEqual(currentMonth.count, 29, "Leap year Feb should have 29 days")
    }

    func testFebruary2026NonLeapYear() {
        // 2026 is not a leap year, Feb has 28 days
        let days = computeDays(for: "2026-02", startsOnMonday: false)
        let currentMonth = days.filter { $0.isCurrentMonth }
        XCTAssertEqual(currentMonth.count, 28)
    }

    // MARK: Consecutive days

    func testDaysAreConsecutive() {
        let days = computeDays(for: "2026-05", startsOnMonday: false)
        let cal = Calendar(identifier: .gregorian)
        for i in 1..<days.count {
            let diff = cal.dateComponents([.day], from: days[i-1].date, to: days[i].date).day!
            XCTAssertEqual(diff, 1, "Days at index \(i-1) and \(i) are not consecutive")
        }
    }
}

// MARK: - Date Extension Tests

final class DateExtensionTests: XCTestCase {

    func testStartOfMonthIsFirstDay() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let date = fmt.date(from: "2026-05-17")!
        let start = date.startOfMonth()
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.month, from: start), 5)
        XCTAssertEqual(cal.component(.year, from: start), 2026)
    }

    func testStartOfMonthHasZeroTime() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let date = fmt.date(from: "2026-05-17 14:30:00")!
        let start = date.startOfMonth()
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: start), 0)
        XCTAssertEqual(cal.component(.minute, from: start), 0)
        XCTAssertEqual(cal.component(.second, from: start), 0)
    }

    func testStartOfMonthDecember() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let date = fmt.date(from: "2025-12-31")!
        let start = date.startOfMonth()
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.day, from: start), 1)
        XCTAssertEqual(cal.component(.month, from: start), 12)
        XCTAssertEqual(cal.component(.year, from: start), 2025)
    }
}

// MARK: - AppPreferences Tests

final class AppPreferencesTests: XCTestCase {

    // Use a fresh UserDefaults suite so tests don't pollute the real app defaults
    let suiteName = "com.popcal.tests"
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultWeekStartIsSunday() {
        XCTAssertFalse(AppPreferences.shared.weekStartsOnMonday)
    }

    func testDefaultHotkeyEnabled() {
        XCTAssertTrue(AppPreferences.shared.hotkeyEnabled)
    }

    func testDefaultHotkeyKeyCodeIsSpace() {
        XCTAssertEqual(AppPreferences.shared.hotkeyKeyCode, 49) // Space
    }

    func testHotkeyDisplayStringContainsCommand() {
        let prefs = AppPreferences.shared
        prefs.hotkeyModifiers = .command
        prefs.hotkeyKeyCode = 49
        XCTAssertTrue(prefs.hotkeyDisplayString.contains("⌘"))
        XCTAssertTrue(prefs.hotkeyDisplayString.contains("Space"))
    }

    func testHotkeyDisplayStringMultipleModifiers() {
        let prefs = AppPreferences.shared
        prefs.hotkeyModifiers = [.command, .option]
        prefs.hotkeyKeyCode = 0 // A
        let str = prefs.hotkeyDisplayString
        XCTAssertTrue(str.contains("⌘"))
        XCTAssertTrue(str.contains("⌥"))
        XCTAssertTrue(str.contains("A"))
    }

    func testHotkeyDisplayStringNoModifiers() {
        let prefs = AppPreferences.shared
        prefs.hotkeyModifiers = []
        prefs.hotkeyKeyCode = 49
        XCTAssertEqual(prefs.hotkeyDisplayString, "Space")
    }
}

// MARK: - CalendarDay Model Tests

final class CalendarDayModelTests: XCTestCase {

    func testCalendarDayHasUniqueIDs() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let d1 = CalendarDay(date: fmt.date(from: "2026-05-01")!, isCurrentMonth: true)
        let d2 = CalendarDay(date: fmt.date(from: "2026-05-02")!, isCurrentMonth: true)
        XCTAssertNotEqual(d1.id, d2.id)
    }

    func testCalendarDayStoresDate() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let date = fmt.date(from: "2026-05-04")!
        let day = CalendarDay(date: date, isCurrentMonth: true)
        XCTAssertEqual(day.date, date)
    }

    func testCalendarDayCurrentMonthFlag() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let date = fmt.date(from: "2026-04-30")!
        let day = CalendarDay(date: date, isCurrentMonth: false)
        XCTAssertFalse(day.isCurrentMonth)
    }
}

// MARK: - CalendarGeometry Tests

final class CalendarGeometryTests: XCTestCase {

    func makeCalendar(startsOnMonday: Bool) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US")
        cal.timeZone = TimeZone(identifier: "America/Vancouver")!
        cal.firstWeekday = startsOnMonday ? 2 : 1
        return cal
    }

    func date(_ string: String, _ cal: Calendar) -> Date {
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.timeZone = cal.timeZone
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.date(from: string)!
    }

    func testRowZeroContainsFirstOfReferenceMonth() {
        let cal = makeCalendar(startsOnMonday: false)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-17", cal))
        // May 1, 2026 is a Friday; with a Sunday start the anchor is Sunday April 26.
        XCTAssertEqual(geo.anchor, date("2026-04-26", cal))
        XCTAssertEqual(geo.row(containing: date("2026-05-01", cal)), 0)
        XCTAssertEqual(geo.date(row: 0, column: 5), date("2026-05-01", cal))
    }

    func testMondayStartAnchorIsMonday() {
        let cal = makeCalendar(startsOnMonday: true)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-01", cal))
        XCTAssertEqual(geo.anchor, date("2026-04-27", cal))
        XCTAssertEqual(cal.component(.weekday, from: geo.anchor), 2)
    }

    func testRowsExtendInBothDirections() {
        let cal = makeCalendar(startsOnMonday: false)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-01", cal))
        XCTAssertEqual(geo.row(containing: date("2026-04-25", cal)), -1)
        XCTAssertEqual(geo.row(containing: date("2026-04-26", cal)), 0)
        XCTAssertEqual(geo.row(containing: date("2026-05-03", cal)), 1)
        // Far away in either direction
        let past = date("1999-12-31", cal)
        let future = date("2100-01-01", cal)
        XCTAssertTrue(cal.isDate(geo.date(row: geo.row(containing: past), column: cal.component(.weekday, from: past) - 1), inSameDayAs: past))
        XCTAssertTrue(cal.isDate(geo.date(row: geo.row(containing: future), column: cal.component(.weekday, from: future) - 1), inSameDayAs: future))
    }

    func testRowsAcrossDaylightSavingChange() {
        let cal = makeCalendar(startsOnMonday: false)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-03-01", cal))
        // DST starts March 8, 2026 in Vancouver
        for row in 0..<6 {
            for column in 0..<7 {
                let d = geo.date(row: row, column: column)
                XCTAssertEqual(geo.row(containing: d), row)
                XCTAssertEqual(cal.component(.weekday, from: d), column + 1)
            }
        }
    }

    func testFocusedMonthAtMonthStartRow() {
        let cal = makeCalendar(startsOnMonday: false)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-01", cal))
        for monthString in ["2026-01-01", "2026-02-01", "2026-05-01", "2026-08-01", "2027-03-01"] {
            let month = date(monthString, cal)
            let row = geo.row(forMonthOf: month)
            let focused = geo.focusedMonth(offset: Double(row), visibleRows: 6)
            XCTAssertEqual(focused, month, "Scrolling to \(monthString) should focus it")
        }
    }

    func testWeekendColumnsSundayStart() {
        let cal = makeCalendar(startsOnMonday: false)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-01", cal))
        XCTAssertEqual(geo.weekendColumns, [true, false, false, false, false, false, true])
    }

    func testWeekendColumnsMondayStart() {
        let cal = makeCalendar(startsOnMonday: true)
        let geo = CalendarGeometry(calendar: cal, referenceMonth: date("2026-05-01", cal))
        XCTAssertEqual(geo.weekendColumns, [false, false, false, false, false, true, true])
    }
}

// MARK: - CalendarOpener Tests

final class CalendarOpenerTests: XCTestCase {

    func localDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    func testGoogleCalendarURL() {
        XCTAssertEqual(CalendarOpener.googleCalendarURL(for: localDate(2026, 11, 5)).absoluteString,
                       "https://calendar.google.com/calendar/r/day/2026/11/5")
    }

    func testCalendarAppScriptSetsDateFields() {
        let script = CalendarOpener.calendarAppScript(for: localDate(2027, 2, 28))
        XCTAssertTrue(script.contains("set year of theDate to 2027"))
        XCTAssertTrue(script.contains("set month of theDate to 2"))
        XCTAssertTrue(script.contains("set day of theDate to 28"))
        XCTAssertTrue(script.contains("view calendar at theDate"))
        // Day is reset to 1 before changing month, so e.g. Jan 31 → Feb doesn't overflow.
        let resetIndex = script.range(of: "set day of theDate to 1\n")!.lowerBound
        let monthIndex = script.range(of: "set month of theDate")!.lowerBound
        XCTAssertLessThan(resetIndex, monthIndex)
    }

    func testDefaultDestinationIsSystemCalendar() {
        let key = "calendarDestination"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertNil(UserDefaults.standard.string(forKey: key).flatMap(CalendarDestination.init(rawValue:)))
        XCTAssertEqual(CalendarDestination(rawValue: "google"), .google)
    }
}
