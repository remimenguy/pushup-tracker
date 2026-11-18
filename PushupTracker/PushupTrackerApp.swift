import SwiftUI

@main
struct PushupTrackerApp: App {
    @State private var history = WorkoutStore()
    @State private var preferences = PlanStore()
    @State private var workoutIsOpen = false
    @State private var today = Date.now
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack {
                    TodayView(history: history, plan: preferences.plan, date: today) {
                        workoutIsOpen = true
                    }
                }
                .tabItem { Label("Aujourd’hui", systemImage: "target") }

                NavigationStack {
                    ProgressScreen(history: history, date: today)
                }
                .tabItem { Label("Progression", systemImage: "chart.bar.xaxis") }

                NavigationStack {
                    SettingsScreen(preferences: preferences)
                }
                .tabItem { Label("Réglages", systemImage: "gearshape") }
            }
            .tint(Palette.accent)
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: $workoutIsOpen) {
                SessionScreen(history: history, plan: preferences.plan)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { today = .now }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
                today = .now
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                today = .now
            }
        }
    }
}

enum Palette {
    static let background = Color(red: 0.051, green: 0.071, blue: 0.098)
    static let card = Color(red: 0.085, green: 0.114, blue: 0.149)
    static let accent = Color(red: 0.86, green: 0.98, blue: 0.43)
    static let muted = Color(red: 0.69, green: 0.74, blue: 0.79)
    static let french = Locale(identifier: "fr_FR")
}

struct ActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(Palette.background)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16))
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.5)
    }
}
