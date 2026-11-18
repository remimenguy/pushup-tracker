import Charts
import SwiftUI

struct ProgressScreen: View {
    let history: WorkoutStore
    let date: Date
    @State private var range = 7

    var body: some View {
        let days = history.days(range, endingAt: date)
        let record = history.dailyTotals().values.max() ?? 0
        let change = (days.last?.total ?? 0) - (days.dropLast().last?.total ?? 0)
        let total = days.reduce(0) { $0 + $1.total }

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Picker("Période", selection: $range) {
                    Text("7 jours").tag(7)
                    Text("30 jours").tag(30)
                }
                .pickerStyle(.segmented)

                if history.loadError != nil {
                    Label("L’historique est indisponible.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Palette.muted)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        metric("Sur la période", value: total)
                        metric("Record journalier", value: record)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Pompes par jour").font(.headline)
                        if total == 0 {
                            Text("Tes prochaines séances apparaîtront ici.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        chart(days)
                        if total > 0 {
                            Text(change == 0 ? "Même total qu’hier" : "\(change > 0 ? "+" : "−")\(repText(abs(change))) par rapport à hier")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    .padding(18)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))

                    if total > 0 {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Détail par jour").font(.headline).padding(.bottom, 6)
                            ForEach(days.reversed()) { day in
                                HStack {
                                    Text(day.date, format: .dateTime.day().month(.wide).locale(Palette.french))
                                    Spacer()
                                    Text(repText(day.total))
                                        .monospacedDigit()
                                        .foregroundStyle(day.total > 0 ? Palette.accent : Palette.muted)
                                }
                                .padding(.vertical, 10)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Palette.background)
        .navigationTitle("Progression")
    }

    private func chart(_ days: [WorkoutDay]) -> some View {
        Chart(days) { day in
            BarMark(x: .value("Jour", day.date, unit: .day), y: .value("Pompes", day.total))
                .cornerRadius(4)
                .foregroundStyle(Palette.accent)
                .accessibilityLabel(Text(day.date, format: .dateTime.day().month().locale(Palette.french)))
                .accessibilityValue(Text(repText(day.total)))
        }
        .chartYScale(domain: 0...max(5, days.map(\.total).max() ?? 0))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) {
                AxisValueLabel(format: .dateTime.day().locale(Palette.french))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4))
        }
        .frame(height: 165)
    }

    private func metric(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.accent)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}
