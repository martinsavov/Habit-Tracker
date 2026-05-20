import SwiftUI
import SwiftData

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]

    @AppStorage("tdeeCalories") private var tdeeCalories: Double = 0
    @AppStorage("userHeight")   private var userHeight: Double = 170
    @AppStorage("userAge")      private var userAge: Double = 30
    @AppStorage("userGender")   private var userGender: String = "male"
    @AppStorage("userActivity") private var userActivity: String = "moderate"

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var searchMealType: MealType? = nil
    @State private var showingTDEESetup = false
    @State private var nutritionTab = 0  // 0 = Log, 1 = Stats

    private var todayEntries: [FoodEntry] {
        let cal = Calendar.current
        return allEntries.filter { cal.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var totalKcal: Double {
        todayEntries.reduce(0) { $0 + $1.totalKcal }
    }

    private var totalProtein: Double {
        todayEntries.compactMap { $0.totalProtein }.reduce(0, +)
    }

    private var totalCarbs: Double {
        todayEntries.compactMap { $0.totalCarbs }.reduce(0, +)
    }

    private var totalFat: Double {
        todayEntries.compactMap { $0.totalFat }.reduce(0, +)
    }

    private var target: Double { tdeeCalories > 0 ? tdeeCalories : 2000 }
    private var remaining: Double { target - totalKcal }

    var body: some View {
        VStack(spacing: 16) {

            // Log / Stats picker
            Picker("View", selection: $nutritionTab) {
                Text("Log").tag(0)
                Text("Stats").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if nutritionTab == 1 {
                NutritionStatsView(allEntries: allEntries, target: target)
            } else {

            // Date navigation
            HStack {
                Button {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                } label: {
                    Image(systemName: "chevron.left").foregroundStyle(.blue)
                }

                Spacer()

                Text(Calendar.current.isDateInToday(selectedDate)
                     ? "Today"
                     : selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.headline)

                Spacer()

                Button {
                    let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    if next <= Calendar.current.startOfDay(for: Date()) {
                        selectedDate = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Calendar.current.isDateInToday(selectedDate) ? Color.secondary : Color.blue)
                }
                .disabled(Calendar.current.isDateInToday(selectedDate))
            }
            .padding(.horizontal)

            // Calorie summary card
            CalorieSummaryCard(
                consumed:  totalKcal,
                target:    target,
                remaining: remaining,
                protein:   totalProtein,
                carbs:     totalCarbs,
                fat:       totalFat,
                onSetup:   { showingTDEESetup = true }
            )
            .padding(.horizontal)

            // Meal sections
            ForEach(MealType.allCases, id: \.self) { meal in
                MealSection(
                    meal:    meal,
                    entries: todayEntries.filter { $0.mealType == meal.rawValue },
                    onAdd: {
                        searchMealType = meal
                    },
                    onDelete: deleteEntry
                )
                .padding(.horizontal)
            }
            } // end log section
        }
        .sheet(item: $searchMealType) { meal in
            FoodSearchView(date: selectedDate, mealType: meal)
        }
        .sheet(isPresented: $showingTDEESetup) {
            TDEESetupSheet(
                height:   $userHeight,
                age:      $userAge,
                gender:   $userGender,
                activity: $userActivity,
                result:   $tdeeCalories
            )
        }
    }

    private func deleteEntry(_ entry: FoodEntry) {
        context.delete(entry)
        do { try context.save() } catch { print("Delete error: \(error)") }
    }
}

// MARK: - Calorie Summary Card

struct CalorieSummaryCard: View {
    let consumed:  Double
    let target:    Double
    let remaining: Double
    let protein:   Double
    let carbs:     Double
    let fat:       Double
    let onSetup:   () -> Void

    private var progress: Double { min(consumed / target, 1.0) }
    private var isOver: Bool { consumed > target }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Calories").font(.headline)
                Spacer()
                Button("Set Target") { onSetup() }
                    .font(.caption).foregroundStyle(.blue)
            }

            HStack(spacing: 20) {
                // Ring
                ZStack {
                    Circle()
                        .stroke(Color(.tertiarySystemBackground), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(isOver ? Color.red : Color.orange,
                                style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(duration: 0.5), value: progress)

                    VStack(spacing: 2) {
                        Text("\(Int(consumed))")
                            .font(.title3).fontWeight(.bold)
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 8) {
                    MacroRow(label: "Target",    value: "\(Int(target)) kcal",    color: .blue)
                    MacroRow(label: remaining >= 0 ? "Remaining" : "Over",
                             value: "\(Int(abs(remaining))) kcal",
                             color: remaining >= 0 ? .green : .red)
                    MacroRow(label: "Protein",   value: String(format: "%.0fg", protein), color: .blue)
                    MacroRow(label: "Carbs",     value: String(format: "%.0fg", carbs),   color: .yellow)
                    MacroRow(label: "Fat",       value: String(format: "%.0fg", fat),     color: .orange)
                }

                Spacer()
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.tertiarySystemBackground))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOver ? Color.red : Color.orange)
                        .frame(width: geo.size.width * progress)
                        .animation(.spring(duration: 0.5), value: progress)
                }
            }
            .frame(height: 8)

            // At this rate line
            if consumed > 0 {
                let dailyDeficit = target - consumed
                let weeklyKg = dailyDeficit * 7 / 7700
                HStack {
                    Image(systemName: weeklyKg > 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(weeklyKg > 0 ? .green : .red)
                    Text(weeklyKg > 0
                         ? String(format: "At this rate: -%.2f kg/week", weeklyKg)
                         : String(format: "At this rate: +%.2f kg/week", abs(weeklyKg)))
                        .font(.caption2)
                        .foregroundStyle(weeklyKg > 0 ? .green : .red)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct MacroRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption).fontWeight(.semibold)
        }
    }
}

// MARK: - Meal Section

struct MealSection: View {
    let meal:     MealType
    let entries:  [FoodEntry]
    let onAdd:    () -> Void
    let onDelete: (FoodEntry) -> Void

    private var totalKcal: Double { entries.reduce(0) { $0 + $1.totalKcal } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(meal.rawValue, systemImage: meal.icon)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(Color(hex: meal.color) ?? .blue)
                Spacer()
                if !entries.isEmpty {
                    Text("\(Int(totalKcal)) kcal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
            }

            if entries.isEmpty {
                Button(action: onAdd) {
                    Text("Add food")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(.tertiarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            } else {
                List {
                    ForEach(entries) { entry in
                        FoodEntryRow(entry: entry)
                            .listRowBackground(Color(.tertiarySystemBackground))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(minHeight: CGFloat(entries.count) * 58)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                    .font(.callout).fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(Int(entry.servingSize))g")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(entry.totalKcal)) kcal")
                    .font(.callout).fontWeight(.semibold)
                    .foregroundStyle(.orange)
                if let p = entry.totalProtein {
                    Text("P: \(String(format: "%.0f", p))g")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - TDEE Setup Sheet

struct TDEESetupSheet: View {
    @Binding var height:   Double
    @Binding var age:      Double
    @Binding var gender:   String
    @Binding var activity: String
    @Binding var result:   Double
    @Environment(\.dismiss) private var dismiss

    @AppStorage("currentWeight") private var currentWeight: Double = 80
    @AppStorage("goalWeight")    private var goalWeight: Double = 0

    // Loss rate options: kg per week
    @AppStorage("lossRateKg") private var lossRateKg: Double = 0.5
    @State private var targetWeight: Double = 75
    @State private var useTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    private let lossRates: [(Double, String, String)] = [
        (0.25, "0.25 kg/week", "Gentle — easier to sustain"),
        (0.5,  "0.5 kg/week",  "Recommended — safe and steady"),
        (0.75, "0.75 kg/week", "Moderate — requires discipline"),
        (1.0,  "1.0 kg/week",  "Aggressive — hard to maintain"),
    ]

    private let activities = [
        ("sedentary", "Sedentary",         "Desk job, little exercise"),
        ("light",     "Lightly Active",    "1-3 days/week exercise"),
        ("moderate",  "Moderately Active", "3-5 days/week exercise"),
        ("active",    "Very Active",       "6-7 days/week exercise"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Details") {
                    Picker("Gender", selection: $gender) {
                        Text("Male").tag("male")
                        Text("Female").tag("female")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", value: $height, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("cm").foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("years", value: $age, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("yrs").foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Current Weight")
                        Spacer()
                        TextField("kg", value: $currentWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }

                Section("Activity Level") {
                    ForEach(activities, id: \.0) { key, name, desc in
                        Button { activity = key } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name).foregroundStyle(.primary).fontWeight(.semibold)
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if activity == key {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Weight Goal") {
                    HStack {
                        Text("Target Weight")
                        Spacer()
                        TextField("kg", value: $targetWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("kg").foregroundStyle(.secondary)
                    }

                    let tolose = max(currentWeight - targetWeight, 0)
                    if tolose > 0 {
                        HStack {
                            Text("To lose")
                            Spacer()
                            Text(String(format: "%.1f kg", tolose))
                                .fontWeight(.semibold).foregroundStyle(.blue)
                        }
                    }
                }

                Section("Loss Rate") {
                    ForEach(lossRates, id: \.0) { rate, label, desc in
                        Button { lossRateKg = rate } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label).foregroundStyle(.primary).fontWeight(.semibold)
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if lossRateKg == rate {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Your Plan") {
                    let tdee    = calculateTDEE()
                    let deficit = lossRateKg * 7700 / 7   // 7700 kcal ≈ 1kg fat
                    let target  = tdee - deficit
                    let tolose  = max(currentWeight - targetWeight, 0)
                    let weeks   = lossRateKg > 0 ? tolose / lossRateKg : 0

                    VStack(alignment: .leading, spacing: 10) {
                        PlanRow(label: "Your TDEE",        value: "\(Int(tdee)) kcal/day",   color: .primary)
                        PlanRow(label: "Daily deficit",    value: "\(Int(deficit)) kcal",    color: .orange)
                        PlanRow(label: "Daily target",     value: "\(Int(target)) kcal/day", color: .blue)
                        if tolose > 0 {
                            PlanRow(label: "Estimated time",
                                    value: weeks < 4
                                        ? String(format: "%.0f weeks", weeks)
                                        : String(format: "%.1f months", weeks / 4.33),
                                    color: .green)
                        }
                        if target < 1200 {
                            Label("Below 1200 kcal/day is not recommended. Choose a gentler rate.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Calorie Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let tdee    = calculateTDEE()
                        let deficit = lossRateKg * 7700 / 7
                        result = max(tdee - deficit, 1200)   // never below 1200
                        goalWeight = targetWeight
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            targetWeight = goalWeight > 0 ? goalWeight : max(currentWeight - 5, 50)
        }
    }

    private func calculateTDEE() -> Double {
        let bmr: Double
        if gender == "male" {
            bmr = 10 * currentWeight + 6.25 * height - 5 * age + 5
        } else {
            bmr = 10 * currentWeight + 6.25 * height - 5 * age - 161
        }
        let multiplier: Double
        switch activity {
        case "sedentary": multiplier = 1.2
        case "light":     multiplier = 1.375
        case "moderate":  multiplier = 1.55
        case "active":    multiplier = 1.725
        default:          multiplier = 1.55
        }
        return bmr * multiplier
    }
}

struct PlanRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(color)
        }
    }
}
