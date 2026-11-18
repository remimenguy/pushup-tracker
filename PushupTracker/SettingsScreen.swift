import SwiftUI
import UIKit

struct SettingsScreen: View {
    let preferences: PlanStore
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = DailyPlan()
    @State private var reminderEnabled = false
    @State private var savedReminderEnabled: Bool?
    @State private var isSaving = false
    @State private var isLoaded = false
    @State private var saveError: SaveError?
    private let reminder = DailyReminder()

    var body: some View {
        Form {
            Section("Séance quotidienne") {
                Stepper("Objectif : \(repText(draft.goal))", value: $draft.goal, in: 1...1_000)
                Stepper("Durée maximale : \(draft.minutes) min", value: $draft.minutes, in: 1...30)
            }

            Section {
                Toggle("Rappel quotidien", isOn: $reminderEnabled)
                    .disabled(savedReminderEnabled == nil)
                if reminderEnabled {
                    DatePicker("Heure", selection: Binding(
                        get: { draft.reminderTime },
                        set: { draft.setReminderTime($0) }
                    ), displayedComponents: .hourAndMinute)
                    .environment(\.locale, Palette.french)
                }
            } footer: {
                Text("Le rappel indique combien de pompes tu as prévu de faire.")
            }
            Section {
                Button("Enregistrer les réglages", action: save)
                    .disabled(savedReminderEnabled == nil || isSaving ||
                              (draft == preferences.plan && reminderEnabled == savedReminderEnabled))
            }
        }
        .disabled(isSaving)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Réglages")
        .onAppear {
            if !isLoaded {
                draft = preferences.plan
                isLoaded = true
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            let active = await reminder.isScheduled()
            guard !Task.isCancelled, !isSaving else { return }
            if savedReminderEnabled == nil || reminderEnabled == savedReminderEnabled { reminderEnabled = active }
            savedReminderEnabled = active
        }
        .alert(item: $saveError) { error in
            switch error {
            case .permission:
                Alert(
                    title: Text("Notifications désactivées"),
                    message: Text("Autorise les notifications de Pushup Tracker dans les réglages de l’iPhone, puis active le rappel ici."),
                    primaryButton: .default(Text("Ouvrir les réglages")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    },
                    secondaryButton: .cancel(Text("Fermer"))
                )
            case .schedule:
                Alert(
                    title: Text("Rappel non enregistré"),
                    message: Text("Vérifie tes réglages et réessaie."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await reminder.update(enabled: reminderEnabled, plan: draft)
                preferences.save(draft)
                savedReminderEnabled = reminderEnabled
            } catch DailyReminder.ReminderError.denied {
                preferences.save(draft)
                savedReminderEnabled = false
                reminderEnabled = false
                saveError = .permission
            } catch {
                saveError = .schedule
            }
        }
    }

    private enum SaveError: String, Identifiable {
        case permission, schedule
        var id: String { rawValue }
    }
}
