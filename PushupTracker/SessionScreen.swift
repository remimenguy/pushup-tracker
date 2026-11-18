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
    @State private var mode = CameraEngine.Mode.front
    @State private var pose: PoseGeometry.Frame?
    @State private var status = CameraEngine.Status.framing
    @State private var cameraTotal = 0
    @State private var reps = 0
    @State private var deadline: Date?
    @State private var countdownEnd: Date?
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
                        } else if let countdownEnd {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let seconds = max(1, Int(ceil(countdownEnd.timeIntervalSince(context.date))))
                                VStack(spacing: 6) {
                                    Text(seconds, format: .number)
                                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                                        .foregroundStyle(Palette.accent)
                                    Text("Mets-toi en position haute, bras tendus.")
                                        .font(.subheadline)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            Picker("Angle de la caméra", selection: $mode) {
                                ForEach(CameraEngine.Mode.allCases, id: \.self) { angle in
                                    Text(angle.title).tag(angle)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(captureInstructions)
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                            Button("Lancer le compteur") {
                                if mode == .front && status != .denied && status != .unavailable {
                                    countdownEnd = Date.now.addingTimeInterval(4)
                                } else {
                                    beginWorkout()
                                }
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
                pose = update.pose
                applyCameraCount(update.repetitions)
            }
        }
        .onChange(of: mode) { _, newMode in
            camera.setMode(newMode)
        }
        .task(id: scenePhase) {
            if scenePhase == .active, workout == nil, !isFinishing {
                await camera.start()
            } else {
                pose = nil
                camera.stop()
            }
        }
        .task(id: countdownEnd) {
            guard let countdownEnd else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, countdownEnd.timeIntervalSinceNow)))
                beginWorkout()
                self.countdownEnd = nil
            } catch {
                return
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
                    CameraPreview(session: camera.session, hasVideo: pose != nil)
                        .accessibilityHidden(true)
                    if let pose {
                        PoseOverlay(frame: pose)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 22))

            if case let .front(arms, legs, _, _) = status {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        limbStatus("Bras", count: arms, color: Palette.accent)
                        limbStatus("Jambes", count: legs, color: .cyan)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        limbStatus("Bras", count: arms, color: Palette.accent)
                        limbStatus("Jambes", count: legs, color: .cyan)
                    }
                }
            }
            Label(cameraMessage, systemImage: trackingIsReady ? "checkmark.circle.fill" : "viewfinder")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(trackingIsReady ? Palette.accent : Palette.muted)

            if status == .denied {
                Button("Autoriser la caméra") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .font(.subheadline)
            }
        }
    }

    private func limbStatus(_ label: String, count: Int, color: Color) -> some View {
        Label("\(label) \(count)/2", systemImage: count == 2 ? "checkmark.circle.fill" : "circle.dashed")
            .font(.caption.weight(.semibold))
            .foregroundStyle(count > 0 ? color : Palette.muted)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel("\(label) : \(count) sur 2")
    }

    private var captureInstructions: String {
        switch mode {
        case .front:
            "Pose l’iPhone debout près du sol, face à toi. Garde ton visage dans le cadre en haut et en bas."
        case .side:
            "Place l’iPhone de profil, à hauteur du sol. Garde le bras et la hanche visibles."
        }
    }

    private var trackingIsReady: Bool {
        switch status {
        case .ready, .front(_, _, true, _): true
        default: false
        }
    }

    private var cameraMessage: String {
        switch status {
        case .framing: mode == .front ? "Cadre-toi de face" : "Cadre-toi de profil"
        case .searching: "Place ton bras et ta hanche dans le cadre"
        case .ready: "Position détectée"
        case .front(_, _, true, _): "Visage détecté"
        case .front(_, _, false, true): "Suivi partiel · remonte pour valider"
        case .front: "Garde ton visage dans le cadre"
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
        .sensoryFeedback(.increase, trigger: cameraTotal)
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

    private func beginWorkout() {
        deadline = Date.now.addingTimeInterval(Double(plan.minutes * 60))
        UIApplication.shared.isIdleTimerDisabled = true
        camera.beginCounting()
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
    let hasVideo: Bool

    func makeUIView(context: Context) -> PreviewSurface {
        let view = PreviewSurface()
        view.preview.videoGravity = .resizeAspect
        view.preview.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewSurface, context: Context) {
        if hasVideo { uiView.orient() }
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
                if connection.videoRotationAngle != 90 { connection.videoRotationAngle = 90 }
                if connection.isVideoMirroringSupported {
                    if connection.automaticallyAdjustsVideoMirroring {
                        connection.automaticallyAdjustsVideoMirroring = false
                    }
                    if !connection.isVideoMirrored { connection.isVideoMirrored = true }
                }
            }
        }
    }
}

private struct PoseOverlay: View {
    let frame: PoseGeometry.Frame
    private typealias Joint = PoseGeometry.Joint

    private static let armSegments: [(Joint, Joint)] = [
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder)
    ]

    private static let legSegments: [(Joint, Joint)] = [
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]

    var body: some View {
        Canvas { context, size in
            let rect = PoseGeometry.previewRect(image: frame.imageSize, in: size)
            let points = frame.points.mapValues { PoseGeometry.previewPoint($0, in: rect) }

            for (segments, color) in [(Self.armSegments, Palette.accent), (Self.legSegments, Color.cyan)] {
                var lines = Path()
                for (start, end) in segments {
                    guard let a = points[start], let b = points[end] else { continue }
                    lines.move(to: a)
                    lines.addLine(to: b)
                }
                context.stroke(lines, with: .color(.black.opacity(0.66)),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round))
                context.stroke(lines, with: .color(color), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }

            for (joint, point) in points {
                let dot = Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(joint.isLegJoint ? .cyan : Palette.accent))
                context.stroke(dot, with: .color(.black.opacity(0.75)), lineWidth: 1.5)
            }
        }
    }
}
