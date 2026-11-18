import SwiftUI

struct TodayView: View {
    let history: WorkoutStore
    let plan: DailyPlan
    let date: Date
    let start: () -> Void

    var body: some View {
        let days = history.days(2, endingAt: date)
        let total = days.last?.total ?? 0
        let yesterday = days.first?.total ?? 0
        let dateLabel = date.formatted(.dateTime.weekday(.wide).day().month().locale(Palette.french))

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(dateLabel.prefix(1).uppercased() + dateLabel.dropFirst())
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.muted)

                VStack(alignment: .leading, spacing: 18) {
                    Text("Objectif du jour").font(.headline)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            score(total)
                            Text("/ \(repText(plan.goal))")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(Palette.muted)
                                .fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            score(total)
                            Text("sur \(repText(plan.goal))").foregroundStyle(Palette.muted)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(repText(total)) sur \(plan.goal)")

                    ProgressView(value: Double(min(total, plan.goal)), total: Double(plan.goal))
                        .accessibilityHidden(true)

                    if total >= plan.goal {
                        Label("Objectif atteint", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    } else {
                        Text("Encore \(repText(plan.goal - total))")
                            .font(.subheadline)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 24))

                Button(action: start) {
                    Label("Démarrer une séance", systemImage: "play.fill")
                }
                .buttonStyle(ActionButtonStyle())

                HStack(spacing: 16) {
                    Label("\(plan.minutes) min max.", systemImage: "timer")
                    Spacer(minLength: 0)
                    Label("\(repText(yesterday)) hier", systemImage: "calendar")
                }
                .font(.subheadline)
                .foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Palette.background)
        .navigationTitle("Aujourd’hui")
    }

    private func score(_ count: Int) -> some View {
        Text(count, format: .number)
            .font(.system(size: 68, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.accent)
            .contentTransition(.numericText())
    }
}
