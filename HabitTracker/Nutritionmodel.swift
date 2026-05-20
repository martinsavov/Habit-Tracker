import SwiftData
import SwiftUI

// MARK: - Meal Type

enum MealType: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }
    case breakfast = "Breakfast"
    case lunch     = "Lunch"
    case dinner    = "Dinner"
    case snack     = "Snack"

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch:     return "sun.max.fill"
        case .dinner:    return "moon.stars.fill"
        case .snack:     return "leaf.fill"
        }
    }

    var color: String {
        switch self {
        case .breakfast: return "#FF9F0A"
        case .lunch:     return "#30D158"
        case .dinner:    return "#5E5CE6"
        case .snack:     return "#FF6B6B"
        }
    }
}

// MARK: - Food Entry (a logged food item)

@Model
final class FoodEntry {
    var id: UUID
    var date: Date
    var mealType: String          // MealType.rawValue
    var foodName: String
    var kcal: Double              // per serving
    var protein: Double?          // grams
    var carbs: Double?            // grams
    var fat: Double?              // grams
    var servingQty: Double        // multiplier e.g. 1.5 = 1.5 servings
    var servingUnit: String       // e.g. "g", "ml", "serving"
    var servingSize: Double       // e.g. 100 (grams per serving)

    init(
        date: Date        = Date(),
        mealType: String  = MealType.lunch.rawValue,
        foodName: String,
        kcal: Double,
        protein: Double?  = nil,
        carbs: Double?    = nil,
        fat: Double?      = nil,
        servingQty: Double   = 1,
        servingUnit: String  = "serving",
        servingSize: Double  = 100
    ) {
        self.id          = UUID()
        self.date        = date
        self.mealType    = mealType
        self.foodName    = foodName
        self.kcal        = kcal
        self.protein     = protein
        self.carbs       = carbs
        self.fat         = fat
        self.servingQty  = servingQty
        self.servingUnit = servingUnit
        self.servingSize = servingSize
    }

    // Total calories accounting for serving quantity
    var totalKcal: Double { kcal * servingQty }
    var totalProtein: Double? { protein.map { $0 * servingQty } }
    var totalCarbs: Double?   { carbs.map   { $0 * servingQty } }
    var totalFat: Double?     { fat.map     { $0 * servingQty } }
}

// MARK: - USDA FoodData Central API models

// Replace YOUR_API_KEY_HERE with your key from https://api.nal.usda.gov
private let usdaAPIKey = "l2xmxs9v7sJAhA3Rf3cUpeKexcGCRNGh7TrnuyL7"

struct USDASearchResponse: Codable {
    let foods: [USDAFood]
}

struct USDAFood: Codable, Identifiable {
    let fdcId: Int
    let description: String
    let foodNutrients: [USDANutrient]
    let servingSize: Double?
    let servingSizeUnit: String?

    var id: String { String(fdcId) }

    var displayName: String {
        description
            .capitalized
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var kcalPer100g: Double {
        nutrientValue(for: 1008) ?? nutrientValue(for: 2047) ?? 0
    }
    var proteinPer100g: Double? { nutrientValue(for: 1003) }
    var carbsPer100g: Double?   { nutrientValue(for: 1005) }
    var fatPer100g: Double?     { nutrientValue(for: 1004) }

    private func nutrientValue(for id: Int) -> Double? {
        foodNutrients.first(where: { $0.nutrientId == id })?.value
    }
}

struct USDANutrient: Codable {
    let nutrientId: Int
    let nutrientName: String?
    let value: Double?
    let unitName: String?
}

// Alias so FoodSearchView doesn't need changing
typealias OFFProduct = USDAFood

// MARK: - USDA FoodData Central API

class FoodAPI {
    static let shared = FoodAPI()

    func search(query: String) async throws -> [USDAFood] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "https://api.nal.usda.gov/fdc/v1/foods/search?query=\(encoded)&pageSize=25&api_key=\(usdaAPIKey)"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url)
        request.setValue("MSHabits/1.0", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)
        let response  = try JSONDecoder().decode(USDASearchResponse.self, from: data)
        return response.foods.filter { $0.kcalPer100g > 0 }
    }
}
