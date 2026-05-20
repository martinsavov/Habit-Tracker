
import SwiftUI
import SwiftData
import Charts

struct NutritionStatsView: View {
    let allEntries: [FoodEntry]
    let target: Double

    @AppStorage("goalWeight")    private var goalWeight: Double = 0
    @AppStorage("currentWeight") private var currentWeight: Double = 80
    @AppStorage("userHeight")    private var userHeight: Double = 170

    var body: some View {
        VStack(spacing: 16) {
            BMICard(weightKg: currentWeight, heightCm: userHeight)
                .padding(.horizontal)

            WeeklySummaryCard(allEntries: allEntries, target: target, goalWeight: goalWeight)
                .padding(.horizontal)

            MacroBreakdownCard(allEntries: allEntries)
                .padding(.horizontal)

            MonthlyHeatmapCard(allEntries: allEntries, target: target)
                .padding(.horizontal)

            ProjectedWeightCard(
                allEntries:    allEntries,
                target:        target,
                currentWeight: currentWeight,
                goalWeight:    goalWeight
            )
            .padding(.horizontal)
        }
    }
}

// MARK: - BMI Card

struct BMICard: View {
    let weightKg: Double
    let heightCm: Double

    private var bmi: Double {
        guard heightCm > 0 else { return 0 }
        let hm = heightCm / 100
        return weightKg / (hm * hm)
    }

    private var category: (String, Color) {
        switch bmi {
        case ..<18.5: return ("Underweight", .blue)
        case 18.5..<25: return ("Normal", .green)
        case 25..<30: return ("Overweight", .orange)
        default: return ("Obese", .red)
        }
    }

    // Position on scale 0-1 for BMI 15-40
    private var scalePosition: Double {
        min(max((bmi - 15) / 25, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BMI").font(.headline)

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f", bmi))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(category.1)
                    Text(category.0)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(category.1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    BMIRangeRow(label: "Underweight", range: "< 18.5", color: .blue,   active: bmi < 18.5)
                    BMIRangeRow(label: "Normal",      range: "18.5–25", color: .green,  active: bmi >= 18.5 && bmi < 25)
                    BMIRangeRow(label: "Overweight",  range: "25–30",   color: .orange, active: bmi >= 25 && bmi < 30)
                    BMIRangeRow(label: "Obese",       range: "> 30",    color: .red,    active: bmi >= 30)
                }
            }

            // Visual scale
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    LinearGradient(
                        colors: [.blue, .green, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(Capsule())

                    // Marker
                    Circle()
                        .fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(radius: 2)
                        .offset(x: geo.size.width * scalePosition - 8)
                }
            }
            .frame(height: 16)

            HStack {
                Text("15").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("18.5").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("25").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("30").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("40").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct BMIRangeRow: View {
    let label: String
    let range: String
    let color: Color
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption)
                .fontWeight(active ? .bold : .regular)
                .foregroundStyle(active ? color : .secondary)
            Spacer()
            Text(range).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let allEntries: [FoodEntry]
    let target: Double
    let goalWeight: Double

    private var last7DaysAvg: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var total = 0.0
        var days  = 0
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayKcal = allEntries
                .filter { cal.isDate($0.date, inSameDayAs: date) }
                .reduce(0) { $0 + $1.totalKcal }
            if dayKcal > 0 { total += dayKcal; days += 1 }
        }
        return days > 0 ? total / Double(days) : 0
    }

    // Weekly deficit → kg lost this week (3500 kcal ≈ 0.45kg / 7700 kcal = 1kg)
    private var projectedWeeklyLoss: Double {
        guard last7DaysAvg > 0 else { return 0 }
        let dailyDeficit = target - last7DaysAvg  // negative = surplus
        return dailyDeficit * 7 / 7700
    }

    private var onTrack: Bool { projectedWeeklyLoss > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week").font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(last7DaysAvg > 0 ? "\(Int(last7DaysAvg))" : "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("avg kcal/day").font(.caption).foregroundStyle(.secondary)
                }

                Divider().frame(height: 50)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                            .foregroundStyle(.blue).font(.caption)
                        Text("Target: \(Int(target)) kcal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if last7DaysAvg > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: onTrack ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(onTrack ? .green : .red).font(.caption)
                            Text(onTrack
                                 ? String(format: "On track to lose %.2f kg", projectedWeeklyLoss)
                                 : String(format: "On track to gain %.2f kg", abs(projectedWeeklyLoss)))
                                .font(.caption)
                                .foregroundStyle(onTrack ? .green : .red)
                        }
                    }
                    if goalWeight > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.orange).font(.caption)
                            Text("Goal: \(String(format: "%.1f", goalWeight)) kg")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            // 7-day bar chart
            if allEntries.count > 0 {
                WeeklyBarChart(allEntries: allEntries, target: target)
                    .frame(height: 80)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct WeeklyBarChart: View {
    let allEntries: [FoodEntry]
    let target: Double

    private struct DayData: Identifiable {
        let id = UUID()
        let label: String
        let kcal: Double
        let date: Date
    }

    private var days: [DayData] {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { i -> DayData? in
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            let kcal = allEntries
                .filter { cal.isDate($0.date, inSameDayAs: date) }
                .reduce(0) { $0 + $1.totalKcal }
            let label = i == 0 ? "Today" : date.formatted(.dateTime.weekday(.narrow))
            return DayData(label: label, kcal: kcal, date: date)
        }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(
                    x: .value("Day", day.label),
                    y: .value("kcal", day.kcal)
                )
                .foregroundStyle(day.kcal > target ? Color.red.opacity(0.7) : Color.blue.opacity(0.7))
                .cornerRadius(4)
            }

            RuleMark(y: .value("Target", target))
                .foregroundStyle(Color.green.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4]))
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
    }
}

// MARK: - Macro Breakdown Card

struct MacroBreakdownCard: View {
    let allEntries: [FoodEntry]

    // Last 7 days averages
    private var avgProtein: Double { avg(for: \.totalProtein) }
    private var avgCarbs:   Double { avg(for: \.totalCarbs) }
    private var avgFat:     Double { avg(for: \.totalFat) }

    private func avg(for keyPath: KeyPath<FoodEntry, Double?>) -> Double {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        var total = 0.0; var days = 0
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dayTotal = allEntries
                .filter { cal.isDate($0.date, inSameDayAs: date) }
                .compactMap { $0[keyPath: keyPath] }
                .reduce(0, +)
            if dayTotal > 0 { total += dayTotal; days += 1 }
        }
        return days > 0 ? total / Double(days) : 0
    }

    private var totalMacroKcal: Double {
        avgProtein * 4 + avgCarbs * 4 + avgFat * 9
    }

    private var proteinPct: Double { totalMacroKcal > 0 ? avgProtein * 4 / totalMacroKcal : 0 }
    private var carbsPct:   Double { totalMacroKcal > 0 ? avgCarbs   * 4 / totalMacroKcal : 0 }
    private var fatPct:     Double { totalMacroKcal > 0 ? avgFat     * 9 / totalMacroKcal : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Macro Breakdown").font(.headline)
            Text("7-day average").font(.caption).foregroundStyle(.secondary)

            if totalMacroKcal > 0 {
                HStack(spacing: 20) {
                    // Pie chart
                    ZStack {
                        MacroArc(start: 0,            end: proteinPct,                color: .blue)
                        MacroArc(start: proteinPct,   end: proteinPct + carbsPct,     color: .yellow)
                        MacroArc(start: proteinPct + carbsPct, end: 1,               color: .orange)
                    }
                    .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 8) {
                        MacroLegendRow(label: "Protein", grams: avgProtein, pct: proteinPct, color: .blue)
                        MacroLegendRow(label: "Carbs",   grams: avgCarbs,   pct: carbsPct,   color: .yellow)
                        MacroLegendRow(label: "Fat",     grams: avgFat,     pct: fatPct,     color: .orange)
                    }
                    Spacer()
                }
            } else {
                Text("Log food for 7 days to see your macro breakdown")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MacroArc: View {
    let start: Double
    let end: Double
    let color: Color

    var body: some View {
        Circle()
            .trim(from: start, to: end)
            .stroke(color, style: StrokeStyle(lineWidth: 16, lineCap: .butt))
            .rotationEffect(.degrees(-90))
    }
}

struct MacroLegendRow: View {
    let label:  String
    let grams:  Double
    let pct:    Double
    let color:  Color

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.0fg", grams)).font(.caption).fontWeight(.semibold)
            Text(String(format: "%.0f%%", pct * 100)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Monthly Heatmap Card

struct MonthlyHeatmapCard: View {
    let allEntries: [FoodEntry]
    let target: Double

    private let cal = Calendar.current

    private func kcal(for date: Date) -> Double {
        allEntries
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.totalKcal }
    }

    private var daysInMonth: [Date] {
        let today      = cal.startOfDay(for: Date())
        let components = cal.dateComponents([.year, .month], from: today)
        guard let first = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: today) else { return [] }
        return range.compactMap { cal.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    // Pad days so grid starts on Monday
    private var paddedDays: [Date?] {
        guard let first = daysInMonth.first else { return [] }
        let weekday = (cal.component(.weekday, from: first) + 5) % 7  // Mon=0
        return Array(repeating: nil, count: weekday) + daysInMonth.map { Optional($0) }
    }

    private var weeks: [[Date?]] {
        stride(from: 0, to: paddedDays.count, by: 7).map {
            Array(paddedDays[$0..<min($0 + 7, paddedDays.count)])
        }
    }

    private func color(for date: Date) -> Color {
        let k = kcal(for: date)
        if k == 0 { return Color(.tertiarySystemBackground) }
        if k <= target { return .green.opacity(0.3 + 0.7 * (k / target)) }
        let over = min((k - target) / target, 1.0)
        return .red.opacity(0.3 + 0.7 * over)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Overview").font(.headline)
            Text(Date().formatted(.dateTime.month(.wide).year()))
                .font(.caption).foregroundStyle(.secondary)

            // Day labels Mon–Sun
            HStack(spacing: 4) {
                ForEach(["Mon","Tue","Wed","Thu","Fri","Sat","Sun"], id: \.self) { d in
                    Text(String(d.prefix(1)))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Calendar grid
            VStack(spacing: 4) {
                ForEach(weeks.indices, id: \.self) { wi in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { di in
                            if let date = weeks[wi][safe: di] ?? nil {
                                let isToday = cal.isDateInToday(date)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color(for: date))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .overlay(
                                        Text("\(cal.component(.day, from: date))")
                                            .font(.system(size: 10))
                                            .fontWeight(isToday ? .bold : .regular)
                                            .foregroundStyle(isToday ? .primary : .secondary)
                                    )
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity, minHeight: 28)
                            }
                        }
                    }
                }
            }

            // Legend
            HStack(spacing: 16) {
                Spacer()
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.7)).frame(width: 12, height: 12)
                    Text("Under target").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.red.opacity(0.7)).frame(width: 12, height: 12)
                    Text("Over target").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(.tertiarySystemBackground)).frame(width: 12, height: 12)
                    Text("No data").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Projected Weight Card

struct ProjectedWeightCard: View {
    let allEntries: [FoodEntry]
    let target: Double
    let currentWeight: Double
    let goalWeight: Double

    private var avgDailyKcal: Double {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        var total = 0.0; var days = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let k = allEntries.filter { cal.isDate($0.date, inSameDayAs: date) }.reduce(0) { $0 + $1.totalKcal }
            if k > 0 { total += k; days += 1 }
        }
        return days > 0 ? total / Double(days) : 0
    }

    private var dailyDeficit: Double { target - avgDailyKcal }
    private var weeklyLossKg: Double { dailyDeficit * 7 / 7700 }

    private var weeksToGoal: Double? {
        guard goalWeight > 0, currentWeight > goalWeight, weeklyLossKg > 0 else { return nil }
        return (currentWeight - goalWeight) / weeklyLossKg
    }

    private var projectedDate: Date? {
        guard let weeks = weeksToGoal else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: Date())
    }

    // Projected weight in 4 weeks based on current average
    private var weightIn4Weeks: Double {
        currentWeight - (weeklyLossKg * 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Projection").font(.headline)

            if avgDailyKcal == 0 {
                Text("Log food for at least a few days to see your projection")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ProjectionRow(
                        label: "30-day avg intake",
                        value: "\(Int(avgDailyKcal)) kcal/day",
                        color: .blue
                    )
                    ProjectionRow(
                        label: "Daily deficit",
                        value: dailyDeficit > 0
                            ? "-\(Int(dailyDeficit)) kcal"
                            : "+\(Int(abs(dailyDeficit))) kcal surplus",
                        color: dailyDeficit > 0 ? .green : .red
                    )
                    ProjectionRow(
                        label: "Weekly change",
                        value: weeklyLossKg > 0
                            ? String(format: "-%.2f kg/week", weeklyLossKg)
                            : String(format: "+%.2f kg/week", abs(weeklyLossKg)),
                        color: weeklyLossKg > 0 ? .green : .red
                    )
                    ProjectionRow(
                        label: "In 4 weeks",
                        value: String(format: "%.1f kg", weightIn4Weeks),
                        color: .orange
                    )
                    if let date = projectedDate {
                        Divider()
                        ProjectionRow(
                            label: "Reach \(String(format: "%.1f", goalWeight))kg goal",
                            value: date.formatted(.dateTime.day().month(.abbreviated).year()),
                            color: .purple
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct ProjectionRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(color)
        }
    }
}

// MARK: - Safe array subscript helper

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
