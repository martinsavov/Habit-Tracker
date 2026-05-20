import SwiftUI
import SwiftData

struct FoodSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let date: Date
    let mealType: MealType

    @State private var query        = ""
    @State private var results:     [OFFProduct] = []
    @State private var isSearching  = false
    @State private var error:       String? = nil
    @State private var selectedFood: OFFProduct? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search food...", text: $query)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    if isSearching {
                        ProgressView().scaleEffect(0.8)
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                            results = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                if let err = error {
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                } else if results.isEmpty && !isSearching && !query.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No results found")
                            .foregroundStyle(.secondary)
                        Text("Try a different search term")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                } else if results.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("Search for a food to log")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                } else {
                    List(results) { product in
                        FoodResultRow(product: product)
                            .listRowBackground(Color(.secondarySystemBackground))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .onTapGesture {
                                selectedFood = product
                            }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }

                Spacer()
            }
            .navigationTitle("\(mealType.rawValue) — Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { product in
                LogFoodSheet(
                    product:  product,
                    date:     date,
                    mealType: mealType
                ) {
                    selectedFood = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        error = nil
        Task {
            do {
                results = try await FoodAPI.shared.search(query: query)
            } catch {
                self.error = "Could not reach food database. Check your connection."
            }
            isSearching = false
        }
    }
}

// MARK: - Food Result Row

struct FoodResultRow: View {
    let product: OFFProduct

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife")
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName)
                    .font(.body).fontWeight(.semibold)
                    .lineLimit(2)
                Text("per 100g")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(product.kcalPer100g)) kcal")
                    .font(.callout).fontWeight(.bold)
                    .foregroundStyle(.orange)
                if let p = product.proteinPer100g {
                    Text("P: \(String(format: "%.0f", p))g")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Log Food Sheet

struct LogFoodSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let product:  OFFProduct
    let date:     Date
    let mealType: MealType
    let onSaved:  () -> Void

    @State private var grams: Double = 100
    @State private var selectedMeal: MealType

    init(product: OFFProduct, date: Date, mealType: MealType, onSaved: @escaping () -> Void) {
        self.product  = product
        self.date     = date
        self.mealType = mealType
        self.onSaved  = onSaved
        _selectedMeal = State(initialValue: mealType)
    }

    private var totalKcal: Double    { product.kcalPer100g * grams / 100 }
    private var totalProtein: Double? { product.proteinPer100g.map { $0 * grams / 100 } }
    private var totalCarbs: Double?   { product.carbsPer100g.map   { $0 * grams / 100 } }
    private var totalFat: Double?     { product.fatPer100g.map     { $0 * grams / 100 } }

    var body: some View {
        NavigationStack {
            Form {
                // Food name
                Section {
                    Text(product.displayName)
                        .font(.headline)
                }

                // Serving size
                Section("Serving Size") {
                    HStack {
                        TextField("Grams", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2).fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text("g")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    // Quick serving buttons
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0], id: \.self) { g in
                                Button("\(Int(g))g") {
                                    grams = g
                                }
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(grams == g ? Color.blue : Color(.tertiarySystemBackground))
                                .foregroundStyle(grams == g ? .white : .primary)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Nutrition summary
                Section("Nutrition") {
                    NutritionRow(label: "Calories", value: "\(Int(totalKcal)) kcal", color: .orange)
                    if let p = totalProtein {
                        NutritionRow(label: "Protein",   value: String(format: "%.1fg", p), color: .blue)
                    }
                    if let c = totalCarbs {
                        NutritionRow(label: "Carbs",     value: String(format: "%.1fg", c), color: .yellow)
                    }
                    if let f = totalFat {
                        NutritionRow(label: "Fat",       value: String(format: "%.1fg", f), color: .red)
                    }
                }

                // Meal type
                Section("Meal") {
                    Picker("Meal type", selection: $selectedMeal) {
                        ForEach(MealType.allCases, id: \.self) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let entry = FoodEntry(
            date:        date,
            mealType:    selectedMeal.rawValue,
            foodName:    product.displayName,
            kcal:        product.kcalPer100g * grams / 100,
            protein:     totalProtein,
            carbs:       totalCarbs,
            fat:         totalFat,
            servingQty:  1,
            servingUnit: "g",
            servingSize: grams
        )
        context.insert(entry)
        do { try context.save() } catch { print("Save error: \(error)") }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
        onSaved()
    }
}

struct NutritionRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}

// MARK: - Make USDAFood hashable for sheet(item:)
extension USDAFood: Hashable {
    static func == (lhs: USDAFood, rhs: USDAFood) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
