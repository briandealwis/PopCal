import SwiftUI

struct CalendarView: View {
    @StateObject private var prefs = AppPreferences.shared
    @State private var displayedMonth: Date = Date().startOfMonth()
    @State private var dragOffset: CGFloat = 0
    @State private var animationOffset: CGFloat = 0
    @State private var isAnimating = false

    private let calendar = Calendar.current
    private let today = Date()

    var body: some View {
        ZStack {
            // Background
            Color(nsColor: .windowBackgroundColor)

            VStack(spacing: 0) {
                headerView
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider().opacity(0.4)

                weekdayRow
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)

                daysGrid
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .offset(y: animationOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isAnimating {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                let threshold: CGFloat = 40
                                if value.translation.height < -threshold {
                                    navigate(direction: 1)
                                } else if value.translation.height > threshold {
                                    navigate(direction: -1)
                                } else {
                                    dragOffset = 0
                                }
                            }
                    )

                Divider().opacity(0.4)

                footerView
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: 300, height: 320)
    }

    // MARK: - Header

    var headerView: some View {
        HStack {
            Button(action: { navigate(direction: -1) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text(monthName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                Text(yearString)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: { navigate(direction: 1) }) {
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

    var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdays, id: \.self) { day in
                Text(day)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Days Grid

    var daysGrid: some View {
        let days = computeDays()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(days.indices, id: \.self) { i in
                let day = days[i]
                DayCell(day: day, today: today, displayedMonth: displayedMonth)
            }
        }
    }

    // MARK: - Footer

    var footerView: some View {
        HStack {
            if !isCurrentMonth {
                Button("Today") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        displayedMonth = Date().startOfMonth()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.accentColor)
            } else {
                Text(todayLabel)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Navigation

    func navigate(direction: Int) {
        guard !isAnimating else { return }
        isAnimating = true
        let outOffset: CGFloat = direction > 0 ? -280 : 280
        let inOffset: CGFloat = direction > 0 ? 280 : -280

        withAnimation(.easeIn(duration: 0.15)) {
            animationOffset = outOffset
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            animationOffset = inOffset
            displayedMonth = calendar.date(byAdding: .month, value: direction, to: displayedMonth) ?? displayedMonth
            dragOffset = 0
            withAnimation(.easeOut(duration: 0.15)) {
                animationOffset = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isAnimating = false
            }
        }
    }

    // MARK: - Computed

    var monthName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM"
        return fmt.string(from: displayedMonth)
    }

    var yearString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy"
        return fmt.string(from: displayedMonth)
    }

    var todayLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, MMMM d"
        return fmt.string(from: today)
    }

    var isCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date().startOfMonth(), toGranularity: .month)
    }

    var orderedWeekdays: [String] {
        let symbols = ["S", "M", "T", "W", "T", "F", "S"]
        if prefs.weekStartsOnMonday {
            return Array(symbols[1...]) + [symbols[0]]
        }
        return symbols
    }

    func computeDays() -> [CalendarDay] {
        var cal = calendar
        cal.firstWeekday = prefs.weekStartsOnMonday ? 2 : 1

        guard let monthInterval = cal.dateInterval(of: .month, for: displayedMonth),
              let firstWeekInterval = cal.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        let startDate = firstWeekInterval.start
        var days: [CalendarDay] = []
        var current = startDate

        // Show up to 6 weeks = 42 cells
        for _ in 0..<42 {
            let isCurrentMonth = cal.isDate(current, equalTo: displayedMonth, toGranularity: .month)
            days.append(CalendarDay(date: current, isCurrentMonth: isCurrentMonth))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }

        // Trim trailing weeks if not needed
        while days.count > 35 {
            let lastWeek = days.suffix(7)
            if lastWeek.allSatisfy({ !$0.isCurrentMonth }) {
                days.removeLast(7)
            } else {
                break
            }
        }

        return days
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
    let day: CalendarDay
    let today: Date
    let displayedMonth: Date

    @Environment(\.colorScheme) var colorScheme
    private let calendar = Calendar.current

    var isToday: Bool { calendar.isDateInToday(day.date) }
    var dayNumber: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        return fmt.string(from: day.date)
    }

    var body: some View {
        ZStack {
            if isToday {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
            }

            Text(dayNumber)
                .font(.system(size: 12, weight: isToday ? .bold : (day.isCurrentMonth ? .regular : .light), design: .rounded))
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .contentShape(Rectangle())
    }

    var textColor: Color {
        if isToday { return .white }
        if !day.isCurrentMonth { return .secondary.opacity(0.5) }
        let weekday = calendar.component(.weekday, from: day.date)
        if weekday == 1 || weekday == 7 { return .secondary }
        return .primary
    }
}

// MARK: - Date helpers

extension Date {
    func startOfMonth() -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: self))!
    }
}
