import SwiftUI
import SwiftData

struct FoodSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FavoriteFood.createdAt, order: .reverse) private var favorites: [FavoriteFood]

    let date: Date
    let mealType: MealType

    @State private var query             = ""
    @State private var results:          [OFFProduct] = []
    @State private var isSearching       = false
    @State private var error:            String? = nil
    @State private var selectedFood:     OFFProduct? = nil
    @State private var showingManual     = false
    @State private var selectedFavorite: FavoriteFood? = nil
    @State private var favoriteToAdd:    OFFProduct? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
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
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding()

                if let err = error {
                    Text(err).font(.callout).foregroundStyle(.secondary).padding()

                } else if query.isEmpty {
                    // Show favorites + manual entry prompt when no search
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            // Manual entry button
                            Button {
                                showingManual = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.green.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "square.and.pencil")
                                            .foregroundStyle(.green)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Add Manually")
                                            .font(.body).fontWeight(.semibold)
                                        Text("Enter name and calories yourself")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                                }
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)

                            // Favorites section
                            if !favorites.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Favourites")
                                        .font(.headline)
                                        .padding(.horizontal)

                                    ForEach(favorites) { fav in
                                        FavoriteRow(favorite: fav) {
                                            selectedFavorite = fav
                                        } onDelete: {
                                            context.delete(fav)
                                            try? context.save()
                                        }
                                        .padding(.horizontal)
                                    }
                                }
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "star.slash")
                                        .font(.largeTitle).foregroundStyle(.secondary.opacity(0.4))
                                    Text("No favourites yet")
                                        .foregroundStyle(.secondary)
                                    Text("Long-press any search result to save it")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 24)
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.top, 4)
                    }

                } else if results.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.secondary)
                        Text("No results found").foregroundStyle(.secondary)
                        Text("Try a different term or add manually")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Add Manually") { showingManual = true }
                            .font(.subheadline).foregroundStyle(.blue)
                    }
                    .padding(.top, 40)

                } else {
                    List(results) { product in
                        FoodResultRow(product: product)
                            .listRowBackground(Color(.secondarySystemBackground))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .onTapGesture { selectedFood = product }
                            .contextMenu {
                                Button {
                                    addToFavorites(product)
                                } label: {
                                    Label("Add to Favourites", systemImage: "star")
                                }
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingManual = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .sheet(item: $selectedFood) { product in
                LogFoodSheet(product: product, date: date, mealType: mealType) {
                    selectedFood = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
                }
            }
            .sheet(item: $selectedFavorite) { fav in
                FavoriteLogSheet(favorite: fav, date: date, mealType: mealType) {
                    selectedFavorite = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
                }
            }
            .sheet(isPresented: $showingManual) {
                ManualFoodEntrySheet(date: date, mealType: mealType) {
                    showingManual = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
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

    private func addToFavorites(_ product: OFFProduct) {
        // Don't add duplicates
        if favorites.contains(where: { $0.name.lowercased() == product.displayName.lowercased() }) {
            return
        }
        let fav = FavoriteFood(
            name:           product.displayName,
            kcalPer100g:    product.kcalPer100g,
            proteinPer100g: product.proteinPer100g,
            carbsPer100g:   product.carbsPer100g,
            fatPer100g:     product.fatPer100g
        )
        context.insert(fav)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Favourite Row

struct FavoriteRow: View {
    let favorite: FavoriteFood
    let onTap:    () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.name).font(.body).fontWeight(.semibold).lineLimit(1)
                Text("per 100g").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(favorite.kcalPer100g)) kcal")
                    .font(.callout).fontWeight(.bold).foregroundStyle(.orange)
                if let p = favorite.proteinPer100g {
                    Text("P: \(String(format: "%.0f", p))g")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { onTap() }
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Remove from Favourites", systemImage: "star.slash")
            }
        }
    }
}

// MARK: - Favourite Log Sheet

struct FavoriteLogSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let favorite:  FavoriteFood
    let date:      Date
    let mealType:  MealType
    let onSaved:   () -> Void

    @State private var grams: Double = 100
    @State private var selectedMeal: MealType

    init(favorite: FavoriteFood, date: Date, mealType: MealType, onSaved: @escaping () -> Void) {
        self.favorite = favorite; self.date = date
        self.mealType = mealType; self.onSaved = onSaved
        _selectedMeal = State(initialValue: mealType)
    }

    private var totalKcal:    Double  { favorite.kcalPer100g * grams / 100 }
    private var totalProtein: Double? { favorite.proteinPer100g.map { $0 * grams / 100 } }
    private var totalCarbs:   Double? { favorite.carbsPer100g.map   { $0 * grams / 100 } }
    private var totalFat:     Double? { favorite.fatPer100g.map     { $0 * grams / 100 } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                        Text(favorite.name).font(.headline)
                    }
                }

                Section("Serving Size") {
                    HStack {
                        TextField("Grams", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2).fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text("g").font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0], id: \.self) { g in
                                Button("\(Int(g))g") { grams = g }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(grams == g ? Color.blue : Color(.tertiarySystemBackground))
                                    .foregroundStyle(grams == g ? .white : .primary)
                                    .clipShape(Capsule()).buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Nutrition") {
                    NutritionRow(label: "Calories", value: "\(Int(totalKcal)) kcal", color: .orange)
                    if let p = totalProtein { NutritionRow(label: "Protein", value: String(format: "%.1fg", p), color: .blue) }
                    if let c = totalCarbs   { NutritionRow(label: "Carbs",   value: String(format: "%.1fg", c), color: .yellow) }
                    if let f = totalFat     { NutritionRow(label: "Fat",     value: String(format: "%.1fg", f), color: .red) }
                }

                Section("Meal") {
                    Picker("Meal type", selection: $selectedMeal) {
                        ForEach(MealType.allCases, id: \.self) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Log Favourite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let entry = FoodEntry(
            date: date, mealType: selectedMeal.rawValue,
            foodName: favorite.name,
            kcal: totalKcal, protein: totalProtein,
            carbs: totalCarbs, fat: totalFat,
            servingQty: 1, servingUnit: "g", servingSize: grams
        )
        context.insert(entry)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(); onSaved()
    }
}

// MARK: - Manual Food Entry Sheet

struct ManualFoodEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let date:     Date
    let mealType: MealType
    let onSaved:  () -> Void

    @State private var name:         String = ""
    @State private var kcal:         String = ""
    @State private var protein:      String = ""
    @State private var carbs:        String = ""
    @State private var fat:          String = ""
    @State private var selectedMeal: MealType
    @State private var saveAsFavorite = false

    init(date: Date, mealType: MealType, onSaved: @escaping () -> Void) {
        self.date = date; self.mealType = mealType; self.onSaved = onSaved
        _selectedMeal = State(initialValue: mealType)
    }

    private var kcalValue:    Double { Double(kcal)    ?? 0 }
    private var proteinValue: Double? { Double(protein).flatMap { $0 > 0 ? $0 : nil } }
    private var carbsValue:   Double? { Double(carbs).flatMap   { $0 > 0 ? $0 : nil } }
    private var fatValue:     Double? { Double(fat).flatMap     { $0 > 0 ? $0 : nil } }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && kcalValue > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food Name") {
                    TextField("e.g. Homemade pasta", text: $name)
                }

                Section("Calories (total for this serving)") {
                    HStack {
                        TextField("0", text: $kcal)
                            .keyboardType(.decimalPad)
                            .font(.title2).fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text("kcal").font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Macros (optional)") {
                    HStack {
                        Text("Protein")
                        Spacer()
                        TextField("0", text: $protein)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Carbs")
                        Spacer()
                        TextField("0", text: $carbs)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Fat")
                        Spacer()
                        TextField("0", text: $fat)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").foregroundStyle(.secondary)
                    }
                }

                Section("Meal") {
                    Picker("Meal type", selection: $selectedMeal) {
                        ForEach(MealType.allCases, id: \.self) { meal in
                            Label(meal.rawValue, systemImage: meal.icon).tag(meal)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Toggle("Save to Favourites", isOn: $saveAsFavorite)
                        .tint(.yellow)
                }
            }
            .navigationTitle("Add Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let entry = FoodEntry(
            date: date, mealType: selectedMeal.rawValue,
            foodName: trimmedName,
            kcal: kcalValue,
            protein: proteinValue,
            carbs: carbsValue,
            fat: fatValue,
            servingQty: 1, servingUnit: "serving", servingSize: 1
        )
        context.insert(entry)

        if saveAsFavorite {
            let fav = FavoriteFood(
                name: trimmedName,
                kcalPer100g: kcalValue,
                proteinPer100g: proteinValue,
                carbsPer100g: carbsValue,
                fatPer100g: fatValue
            )
            context.insert(fav)
        }

        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(); onSaved()
    }
}

// MARK: - Food Result Row (unchanged)

struct FoodResultRow: View {
    let product: OFFProduct

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "fork.knife").foregroundStyle(.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(product.displayName).font(.body).fontWeight(.semibold).lineLimit(2)
                Text("per 100g").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(product.kcalPer100g)) kcal")
                    .font(.callout).fontWeight(.bold).foregroundStyle(.orange)
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

// MARK: - Log Food Sheet (unchanged)

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
        self.product = product; self.date = date
        self.mealType = mealType; self.onSaved = onSaved
        _selectedMeal = State(initialValue: mealType)
    }

    private var totalKcal:    Double  { product.kcalPer100g * grams / 100 }
    private var totalProtein: Double? { product.proteinPer100g.map { $0 * grams / 100 } }
    private var totalCarbs:   Double? { product.carbsPer100g.map   { $0 * grams / 100 } }
    private var totalFat:     Double? { product.fatPer100g.map     { $0 * grams / 100 } }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(product.displayName).font(.headline) }

                Section("Serving Size") {
                    HStack {
                        TextField("Grams", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                            .font(.title2).fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text("g").font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0], id: \.self) { g in
                                Button("\(Int(g))g") { grams = g }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(grams == g ? Color.blue : Color(.tertiarySystemBackground))
                                    .foregroundStyle(grams == g ? .white : .primary)
                                    .clipShape(Capsule()).buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Nutrition") {
                    NutritionRow(label: "Calories", value: "\(Int(totalKcal)) kcal", color: .orange)
                    if let p = totalProtein { NutritionRow(label: "Protein", value: String(format: "%.1fg", p), color: .blue) }
                    if let c = totalCarbs   { NutritionRow(label: "Carbs",   value: String(format: "%.1fg", c), color: .yellow) }
                    if let f = totalFat     { NutritionRow(label: "Fat",     value: String(format: "%.1fg", f), color: .red) }
                }

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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let entry = FoodEntry(
            date: date, mealType: selectedMeal.rawValue,
            foodName: product.displayName,
            kcal: product.kcalPer100g * grams / 100,
            protein: totalProtein, carbs: totalCarbs, fat: totalFat,
            servingQty: 1, servingUnit: "g", servingSize: grams
        )
        context.insert(entry)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss(); onSaved()
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

extension USDAFood: Hashable {
    static func == (lhs: USDAFood, rhs: USDAFood) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
