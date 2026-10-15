import Charts
import SwiftUI

struct TodayCard: View {
    let day: DaySummary

    private var domain: ClosedRange<Date> { day.start...max(day.now, day.start.addingTimeInterval(3 * 3600)) }

    private var ticks: [Date] {
        let hours = [0, 6, 12, 18]
            .compactMap { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: day.start) }
            .filter { day.now.timeIntervalSince($0) >= 2 * 3600 }
        return hours + [day.now]
    }

    private var peak: Int { max(1, day.hours.map { abs($0.watts) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if day.isEmpty {
                Text("No readings yet today.").font(.subheadline).foregroundStyle(Palette.label)
            } else {
                header("CHARGE") {
                    if let low = day.low, let high = day.high {
                        Text("low \("\(low) %") · high \("\(high) %")")
                    }
                }
                charge
                header("POWER") {
                    Text("charge").foregroundStyle(Palette.good) + Text(verbatim: " · ") + Text("discharge").foregroundStyle(Palette.warn)
                }
                .padding(.top, 6)
                power
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.cardEdge, lineWidth: 0.5))
    }

    private var charge: some View {
        Chart {
            ForEach(Array(day.segments.enumerated()), id: \.offset) { i, segment in
                ForEach(segment.samples, id: \.time) { s in
                    LineMark(x: .value("Time", s.time), y: .value("Charge", s.socPct), series: .value("Segment", i))
                        .foregroundStyle(Palette.good)
                        .lineStyle(segment.dotted
                            ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5])
                            : StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            RuleMark(x: .value("Time", day.now))
                .foregroundStyle(Color(hex: 0x48484A))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let last = day.segments.last?.samples.last {
                PointMark(x: .value("Time", last.time), y: .value("Charge", last.socPct))
                    .foregroundStyle(Palette.good)
                    .symbolSize(100)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0, 50, 100]) { _ in AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.track) }
        }
        .frame(height: 140)
    }

    private var power: some View {
        Chart {
            ForEach(day.hours, id: \.hour) { bar in
                BarMark(x: .value("Hour", bar.hour, unit: .hour), y: .value("Power", bar.watts))
                    .foregroundStyle(bar.watts > 0 ? Palette.good : Palette.warn)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Power", 0)).foregroundStyle(Color(hex: 0x38383A))
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: -peak...peak)
        .chartPlotStyle { $0.clipped() }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { v in
                AxisValueLabel {
                    if v.as(Date.self) == day.now {
                        Text("now")
                    } else if let date = v.as(Date.self) {
                        Text(verbatim: String(format: "%02d", Calendar.current.component(.hour, from: date)))
                    }
                }
            }
        }
        .frame(height: 84)
    }

    private func header<Trailing: View>(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .bold, design: .rounded)).tracking(1.6).foregroundStyle(Palette.label)
            Spacer()
            trailing().font(.system(size: 13, design: .rounded)).foregroundStyle(Palette.label)
        }
    }
}

struct TodayNumbers: View {
    let day: DaySummary

    var body: some View {
        HStack(spacing: 0) {
            cell("Charged", kWh(day.chargedWh))
            Divider()
            cell("Used", kWh(day.usedWh))
            Divider()
            cell("On battery", formatDuration(day.onBattery / 3600))
        }
        .listRowInsets(EdgeInsets())
    }

    private func kWh(_ wh: Double) -> String {
        String(localized: "\((wh / 1000).formatted(.number.precision(.fractionLength(1)))) kWh")
    }

    private func cell(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).foregroundStyle(Palette.label)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
