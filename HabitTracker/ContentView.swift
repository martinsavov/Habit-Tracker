import SwiftUI

struct ContentView: View {
    @AppStorage("colorScheme") private var colorSchemePref: String = "system"
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today",    systemImage: "checkmark.circle.fill") }
                .tag(0)

            AllHabitsView()
                .tabItem { Label("Habits",   systemImage: "list.bullet.circle.fill") }
                .tag(1)

            FastingView()
                .tabItem { Label("Fasting", systemImage: "timer") }
                .tag(2)

            WeightView()
                .tabItem { Label("Weight", systemImage: "scalemass.fill") }
                .tag(3)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(4)
        }
        .tint(.blue)
        .preferredColorScheme(resolvedColorScheme)
    }

    private var resolvedColorScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil  // follows system
        }
    }
}
