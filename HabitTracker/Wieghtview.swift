import SwiftUI
import SwiftData
import Charts

struct WeightView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]
    @AppStorage("goalWeight") private var goalWeight: Double = 0
    @State private var showingAddWeight = false
    @State private var showingGoalSheet = false
    @State private var selectedSection = 0

    private var sortedEntries: [WeightEntry] {
        entries.sorted { $0.date < $1.date }
    }

    private var latest: WeightEntry? { entries.first }

    private var change: Double? {
        guard entries.count >= 2 else { return nil }
        return entries[0].kg - entries[1].kg
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {

                    // Segment picker
                    Picker("Section", selection: $selectedSection) {
                        Text("Weight").tag(0)
                        Text("Nutrition").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if selectedSection == 1 {
                        NutritionView()
                    } else {

                    // Current weight card
                    CurrentWeightCard(
                        latest:    latest,
                        change:    change,
                        goal:      goalWeight > 0 ? goalWeight : nil,
                        onAdd:     { showingAddWeight = true },
                        onSetGoal: { showingGoalSheet = true }
                    )
                    .padding(.horizontal)

                    // Chart with its own range selector
                    if sortedEntries.count >= 2 {
                        WeightChartView(allEntries: sortedEntries, goal: goalWeight > 0 ? goalWeight : nil)
                            .padding(.horizontal)
                    }

                    // History list — always all-time stats
                    if !entries.isEmpty {
                        WeightHistoryList(entries: entries)
                            .padding(.horizontal)
                    }
                    } // end weight section
                }
                .padding(.bottom, 32)
                .padding(.top, 8)
            }
            .navigationTitle(selectedSection == 0 ? "Body" : "Nutrition")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedSection == 0 {
                        Button {
                            showingAddWeight = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingAddWeight) {
                AddWeightSheet()
            }
            .sheet(isPresented: $showingGoalSheet) {
                GoalWeightSheet(goalWeight: $goalWeight)
            }
        }
    }
}

// MARK: - Current Weight Card

struct CurrentWeightCard: View {
    let latest: WeightEntry?
    let change: Double?
    let goal: Double?
    let onAdd: () -> Void
    let onSetGoal: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Weight")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let w = latest {
                        Text(String(format: "%.1f kg", w.kg))
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                        Text(w.date.formatted(.dateTime.day().month(.abbreviated)))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text("No entries yet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    // Change indicator
                    if let c = change {
                        HStack(spacing: 4) {
                            Image(systemName: c < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                                .foregroundStyle(c < 0 ? .green : .red)
                            Text(String(format: "%+.1f kg", c))
                                .font(.callout).fontWeight(.semibold)
                                .foregroundStyle(c < 0 ? .green : .red)
                        }
                    }

                    // Goal indicator
                    if let g = goal, let w = latest {
                        let diff = w.kg - g
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Goal: \(String(format: "%.1f kg", g))")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(diff <= 0
                                 ? "Goal reached! 🎉"
                                 : String(format: "%.1f kg to go", diff))
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(diff <= 0 ? .green : .blue)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: onAdd) {
                    Label("Log Weight", systemImage: "plus")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onSetGoal) {
                    Label(goal != nil ? "Edit Goal" : "Set Goal", systemImage: "target")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color(.tertiarySystemBackground))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Chart Range

enum ChartRange: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week:        return 7
        case .month:        return 30
        case .threeMonths:  return 90
        case .sixMonths:    return 180
        case .all:          return nil
        }
    }

    // How the x-axis should be stepped for this range, to avoid label overlap
    var axisStrideDays: Int {
        switch self {
        case .week:        return 1     // show every day
        case .month:        return 7     // show one label per week
        case .threeMonths:  return 30    // show one label per month
        case .sixMonths:    return 30    // show ~6 labels
        case .all:          return 30    // fallback, refined dynamically below
        }
    }
}

// MARK: - Weight Chart

struct WeightChartView: View {
    let allEntries: [WeightEntry]
    let goal: Double?

    @State private var range: ChartRange = .week

    // Explicit domain for the x-axis, independent of where the actual data points sit.
    // This ensures Week always shows Mon–Sun, Month always shows ~4 weeks, etc.
    private var xDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        switch range {
        case .week:
            var weekCal = cal
            weekCal.firstWeekday = 2 // Monday
            let interval = weekCal.dateInterval(of: .weekOfYear, for: today) ?? DateInterval(start: today, end: today)
            let end = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            return interval.start...end

        case .month:
            let start = cal.date(byAdding: .day, value: -29, to: today) ?? today
            return start...today

        case .threeMonths:
            let start = cal.date(byAdding: .day, value: -89, to: today) ?? today
            return start...today

        case .sixMonths:
            let start = cal.date(byAdding: .day, value: -179, to: today) ?? today
            return start...today

        case .all:
            let first = allEntries.first?.date ?? today
            return cal.startOfDay(for: first)...today
        }
    }

    private var filteredEntries: [WeightEntry] {
        if range == .week {
            // Always Monday–Sunday of the current week, regardless of today's weekday
            var cal = Calendar.current
            cal.firstWeekday = 2 // Monday
            let today = Date()
            guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today) else {
                return allEntries
            }
            let filtered = allEntries.filter {
                $0.date >= weekInterval.start && $0.date < weekInterval.end
            }
            return filtered.count >= 2 ? filtered : Array(allEntries.suffix(2))
        }

        guard let days = range.days else { return allEntries }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
        let filtered = allEntries.filter { $0.date >= cutoff }
        // Always show at least the 2 most recent points so the chart isn't empty
        // if entries are sparse within the selected range.
        return filtered.count >= 2 ? filtered : Array(allEntries.suffix(2))
    }

    private var minY: Double {
        let min = filteredEntries.map { $0.kg }.min() ?? 0
        return (goal.map { Swift.min($0, min) } ?? min) - 2
    }
    private var maxY: Double {
        let max = filteredEntries.map { $0.kg }.max() ?? 0
        return (goal.map { Swift.max($0, max) } ?? max) + 2
    }

    private func axisLabel(for date: Date) -> String {
        let cal = Calendar.current
        switch range {
        case .week:
            // e.g. "Mon 14"
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            let day = cal.component(.day, from: date)
            return "\(weekday) \(day)"
        case .month:
            // ISO week number, e.g. "W29"
            let week = cal.component(.weekOfYear, from: date)
            return "W\(week)"
        case .threeMonths, .sixMonths, .all:
            return date.formatted(.dateTime.month(.abbreviated))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Progress").font(.headline)
                Spacer()
            }

            // Range picker
            Picker("Range", selection: $range) {
                ForEach(ChartRange.allCases) { r in
                    Text(r.rawValue).tag(r)
                }
            }
            .pickerStyle(.segmented)

            Chart {
                ForEach(filteredEntries) { entry in
                    LineMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.kg)
                    )
                    .foregroundStyle(Color.blue)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", entry.date),
                        yStart: .value("Min", minY),
                        yEnd: .value("Weight", entry.kg)
                    )
                    .foregroundStyle(Color.blue.opacity(0.08))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.kg)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(30)
                }

                if let g = goal {
                    RuleMark(y: .value("Goal", g))
                        .foregroundStyle(Color.green.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5]))
                        .annotation(position: .trailing) {
                            Text("Goal")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        }
                }
            }
            .chartYScale(domain: minY...maxY)
            .chartXScale(domain: xDomain)
            .chartXAxis {
                switch range {
                case .week:
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                        .font(.caption2)
                        AxisGridLine()
                    }
                case .month:
                    AxisMarks(values: .stride(by: .weekOfYear)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                        .font(.caption2)
                        AxisGridLine()
                    }
                case .threeMonths, .sixMonths, .all:
                    AxisMarks(values: .stride(by: .month)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(for: date))
                            }
                        }
                        .font(.caption2)
                        AxisGridLine()
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f", v))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 200)
            .animation(.easeInOut(duration: 0.25), value: range)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Weight History List (always all-time)

struct WeightHistoryList: View {
    @Environment(\.modelContext) private var context
    let entries: [WeightEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").font(.headline)

            // Stats — all-time, unaffected by chart range
            if entries.count >= 2 {
                let weights = entries.map { $0.kg }
                HStack(spacing: 12) {
                    MiniWeightStat(
                        label: "Highest",
                        value: String(format: "%.1f kg", weights.max() ?? 0),
                        color: .red
                    )
                    MiniWeightStat(
                        label: "Lowest",
                        value: String(format: "%.1f kg", weights.min() ?? 0),
                        color: .green
                    )
                    MiniWeightStat(
                        label: "Average",
                        value: String(format: "%.1f kg", weights.reduce(0, +) / Double(weights.count)),
                        color: .blue
                    )
                }
            }

            List {
                ForEach(entries) { entry in
                    WeightHistoryRow(entry: entry)
                        .listRowBackground(Color(.tertiarySystemBackground))
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                }
            }
            .listStyle(.plain)
            .scrollDisabled(true)
            .frame(minHeight: CGFloat(min(entries.count, 10)) * 56)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func deleteEntry(_ entry: WeightEntry) {
        context.delete(entry)
        do { try context.save() } catch { print("Delete error: \(error)") }
    }
}

struct MiniWeightStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.callout).fontWeight(.bold).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WeightHistoryRow: View {
    let entry: WeightEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.1f kg", entry.kg))
                    .font(.body).fontWeight(.semibold)
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "scalemass.fill")
                .foregroundStyle(.blue.opacity(0.5))
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Add Weight Sheet

struct AddWeightSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WeightEntry.date, order: .reverse) private var entries: [WeightEntry]

    @State private var kg: Double = 70.0
    @State private var date: Date = Date()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Weight") {
                    HStack {
                        TextField("Weight", value: $kg, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("kg")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section("Date & Time") {
                    DatePicker("Logged at", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Log Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Default to last logged weight if available
            if let last = entries.first {
                kg = last.kg
            }
        }
    }

    private func save() {
        let entry = WeightEntry(date: date, kg: kg)
        context.insert(entry)
        do { try context.save() } catch { print("Save error: \(error)") }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Goal Weight Sheet

struct GoalWeightSheet: View {
    @Binding var goalWeight: Double
    @Environment(\.dismiss) private var dismiss
    @State private var localGoal: Double = 70.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Weight") {
                    HStack {
                        TextField("Goal", value: $localGoal, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("kg")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    Button("Remove Goal", role: .destructive) {
                        goalWeight = 0
                        dismiss()
                    }
                }
            }
            .navigationTitle("Goal Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        goalWeight = localGoal
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            localGoal = goalWeight > 0 ? goalWeight : 70.0
        }
    }
}
