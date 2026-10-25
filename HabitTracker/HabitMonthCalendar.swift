import SwiftUI

// Month-at-a-time completion calendar for a single habit (Mon-first).
// Read-only: it only reads the habit's existing entries.

struct HabitMonthCalendar: View {
    let habit: Habit
    @Binding var monthOffset: Int   // 0 = current month, negative = earlier

    private enum CellState { case done, missed, today, future, off }

    private var cal: Calendar { Calendar.current }
    private var today: Date { cal.startOfDay(for: Date()) }

    private var monthStart: Date {
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        return cal.date(byAdding: .month, value: monthOffset, to: thisMonth) ?? thisMonth
    }

    private var createdMonthStart: Date {
        let created = cal.startOfDay(for: habit.createdAt)
        return cal.date(from: cal.dateComponents([.year, .month], from: created)) ?? created
    }

    private var canGoBack: Bool { monthStart > createdMonthStart }
    private var canGoForward: Bool { monthOffset < 0 }

    private var leadingBlanks: Int { habitWeekday(from: monthStart) }   // Mon=0
    private var dayCount: Int { cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30 }

    private let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    // Rows of 7 cells (nil = empty cell). A plain VStack/HStack grid is used on
    // purpose: LazyVGrid inside a List row can trigger a recursive layout loop.
    private var weekRows: [[Int?]] {
        var cells: [Int?] = Array(repeating: nil, count: leadingBlanks)
        cells += (1...dayCount).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        let daySet = habit.completedDaySet()

        VStack(spacing: 6) {
            monthHeader

            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(weekdayLetters[i])
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 20)
                    }
                }
                ForEach(Array(weekRows.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            if let day = week[i] {
                                dayCell(day: day, daySet: daySet)
                            } else {
                                Color.clear
                                    .frame(width: 38, height: 38)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }

            legend
        }
    }

    // MARK: Header

    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation(.snappy(duration: 0.25)) { monthOffset -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 36, alignment: .leading)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            Spacer()
            Text(monthStart.formatted(.dateTime.month(.wide).year()))
                .font(.subheadline.weight(.semibold))
            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.25)) { monthOffset += 1 }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 36, alignment: .trailing)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
    }

    // MARK: Day cell

    private func dayCell(day: Int, daySet: Set<Date>) -> some View {
        let date = cal.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let state = cellState(for: date, daySet: daySet)
        let color = habit.color

        return Text("\(day)")
            .font(.system(size: 15, weight: state == .done || state == .today ? .semibold : .regular))
            .foregroundStyle(textColor(for: state, color: color))
            .frame(width: 38, height: 38)
            .background(Circle().fill(fillColor(for: state, color: color)))
            .overlay(Circle().stroke(state == .today ? color : .clear, lineWidth: 1.5))
            .frame(maxWidth: .infinity)
    }

    private func cellState(for date: Date, daySet: Set<Date>) -> CellState {
        if daySet.contains(date) { return .done }
        if date > today { return .future }
        let scheduled = habit.isScheduled(for: date)
        if date == today { return scheduled ? .today : .off }
        if !scheduled || date < cal.startOfDay(for: habit.createdAt) { return .off }
        return .missed
    }

    private func fillColor(for state: CellState, color: Color) -> Color {
        switch state {
        case .done:   return color
        case .missed: return color.opacity(0.12)
        default:      return .clear
        }
    }

    private func textColor(for state: CellState, color: Color) -> Color {
        switch state {
        case .done:   return isLight(color) ? .black : .white
        case .today:  return color
        case .missed: return .secondary
        case .future, .off: return Color(.tertiaryLabel)
        }
    }

    // Light habit colours (e.g. yellow) need dark text on the filled circle.
    private func isLight(_ color: Color) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.7
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Done") { Circle().fill(habit.color) }
            legendItem("Missed") { Circle().fill(habit.color.opacity(0.12)) }
            legendItem("Today") { Circle().stroke(habit.color, lineWidth: 1.5) }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func legendItem<S: View>(_ title: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 6) {
            swatch().frame(width: 10, height: 10)
            Text(title)
        }
    }
}
