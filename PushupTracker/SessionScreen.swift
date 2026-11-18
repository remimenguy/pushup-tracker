@preconcurrency import AVFoundation
import SwiftUI
import UIKit

struct SessionScreen: View {
    let history: WorkoutStore
    let plan: DailyPlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = CameraEngine()
    @State private var status = CameraEngine.Status.framing
    @State private var cameraTotal = 0
    @State private var reps = 0
    @State private var deadline: Date?
    @State private var workout: Workout?
    @State private var isFinishing = false
    @State private var isSaved = false
    @State private var saveFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let workout {
                        summary(workout)
                    } else {
                        cameraPanel
                        if let deadline {
                            liveControls(deadline)
                        } else {
                            Text("Pose l’iPhone à la verticale, à hauteur du sol. Place-toi de profil, avec le bras et la hanche visibles.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                            Button("Lancer le compteur") {
                                deadline = Date.now.addingTimeInterval(Double(plan.minutes * 60))
                                UIApplication.shared.isIdleTimerDisabled = true
                                camera.beginCounting()
                            }
                            .buttonStyle(ActionButtonStyle())
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.background)
            .navigationTitle(workout == nil ? "Séance de pompes" : "Séance terminée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if deadline == nil && workout == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer", action: { dismiss() })
                    }
                }
            }
        }
        .tint(Palette.accent)
        .task {
            for await update in camera.updates {
                guard !Task.isCancelled else { return }
                status = update.status
                applyCameraCount(update.repetitions)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active, workout == nil, !isFinishing {
                await camera.start()
            } else {
                camera.stop()
            }
        }
        .task(id: deadline) {
            guard let deadline else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                finish(at: deadline)
            } catch {
                return
            }
        }
        .onDisappear {
            camera.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .alert("Historique indisponible", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette séance n’a pas été enregistrée. Tu peux réessayer depuis le récapitulatif.")
        }
    }

    private var cameraPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22).fill(Palette.card)
                if status == .denied || status == .unavailable {
                    Image(systemName: "video.slash")
                        .font(.system(size: 37, weight: .light))
                        .foregroundStyle(Palette.muted)
                } else {
                    CameraPreview(session: camera.session)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 22))

            Label(cameraMessage, systemImage: status == .ready ? "checkmark.circle.fill" : "viewfinder")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(status == .ready ? Palette.accent : Palette.muted)

            if status == .denied {
                Button("Autoriser la caméra") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline)
            }
        }
    }

    private var cameraMessage: String {
        switch status {
        case .framing: "Cadre-toi de profil"
        case .searching: "Place ton bras et ta hanche dans le cadre"
        case .ready: "Position détectée"
        case .denied, .unavailable: "Caméra indisponible · saisie manuelle possible"
        }
    }

    private func liveControls(_ deadline: Date) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button { reps = max(0, reps - 1) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 30))
                        .frame(width: 50, height: 50)
                }
                .disabled(reps == 0)
                .accessibilityLabel("Retirer une pompe")

                VStack(spacing: 0) {
                    Text(reps, format: .number)
                        .font(.system(size: 58, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.accent)
                    Text("Pompes").foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)

                Button { reps += 1 } label: {
                    Image(systemName: "plus.circle").font(.system(size: 30))
                        .frame(width: 50, height: 50)
                }
                .accessibilityLabel("Ajouter une pompe")
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let seconds = Int(max(0, ceil(deadline.timeIntervalSince(context.date))))
                Label(String(format: "%02d:%02d", seconds / 60, seconds % 60), systemImage: "timer")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .accessibilityLabel("Temps restant : \(seconds / 60) minutes, \(seconds % 60) secondes")
            }
            Button("Terminer et enregistrer") { finish(at: min(.now, deadline)) }
                .buttonStyle(ActionButtonStyle())
        }
        .disabled(isFinishing)
    }

    private func summary(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(repText(workout.reps))
                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                .foregroundStyle(Palette.accent)
            if workout.reps > 0 && !isSaved {
                Button("Réessayer l’enregistrement") { save(workout) }.buttonStyle(ActionButtonStyle())
                Button("Fermer sans enregistrer") { dismiss() }
            } else {
                if workout.reps > 0 {
                    Label("Ajouté au total du jour de la séance", systemImage: "checkmark.circle")
                        .foregroundStyle(Palette.muted)
                }
                Button("Retour à Aujourd’hui") { dismiss() }.buttonStyle(ActionButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyCameraCount(_ newTotal: Int) {
        guard newTotal > cameraTotal else { return }
        reps += newTotal - cameraTotal
        cameraTotal = newTotal
    }

    private func finish(at date: Date) {
        guard workout == nil, !isFinishing else { return }
        isFinishing = true
        Task {
            let total = await camera.finishCounting()
            applyCameraCount(total)
            UIApplication.shared.isIdleTimerDisabled = false
            let completed = Workout(id: UUID(), date: date, reps: reps)
            workout = completed
            deadline = nil
            isFinishing = false
            save(completed)
        }
    }

    private func save(_ workout: Workout) {
        do {
            try history.add(workout)
            isSaved = true
        } catch {
            saveFailed = true
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.videoGravity = .resizeAspect
        view.preview.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        uiView.orient()
    }

    final class PreviewSurface: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var preview: AVCaptureVideoPreviewLayer {
            // UIKit creates this layer using layerClass above.
            layer as! AVCaptureVideoPreviewLayer
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            orient()
        }

        func orient() {
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
