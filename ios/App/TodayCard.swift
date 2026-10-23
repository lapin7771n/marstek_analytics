import Charts
import SwiftUI

enum HomeRange: Hashable {
    case today, week
}

struct TodayCard: View {
    let day: DaySummary
    let week: [DayTotal]
    @Binding var range: HomeRange

    private var domain: ClosedRange<Date> { day.start...max(day.now, day.start.addingTimeInterval(3 * 3600)) }

    private var hourTicks: [Date] {
        [0, 6, 12, 18]
            .compactMap { Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: day.start) }
            .filter { day.now.timeIntervalSince($0) >= 2 * 3600 }
    }

    private var peak: Int { max(1, day.hours.map { abs($0.watts) }.max() ?? 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Range", selection: $range) {
                Text("Today").tag(HomeRange.today)
                Text("Week").tag(HomeRange.week)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch range {
            case .week:
                WeekCard(week: week)
            case .today:
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
            AxisMarks(values: hourTicks) { v in
                AxisValueLabel {
                    if let date = v.as(Date.self) {
                        Text(verbatim: String(format: "%02d", Calendar.current.component(.hour, from: date)))
                    }
                }
            }
            AxisMarks(values: [day.now]) { _ in
                AxisValueLabel(anchor: .topTrailing) { Text("now") }
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

struct WeekCard: View {
    let week: [DayTotal]

    private var peak: Double { max(0.1, week.map { max($0.chargedWh, $0.usedWh) }.max() ?? 0) / 1000 }

    var body: some View {
        Chart {
            ForEach(week, id: \.day) { total in
                BarMark(x: .value("Day", total.day, unit: .day), y: .value("Charged", total.chargedWh / 1000))
                    .foregroundStyle(Palette.good)
                    .cornerRadius(3)
                BarMark(x: .value("Day", total.day, unit: .day), y: .value("Used", -total.usedWh / 1000))
                    .foregroundStyle(Palette.warn)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Color(hex: 0x38383A))
        }
        .chartYScale(domain: -peak...peak)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: week.map(\.day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        if Calendar.current.isDateInToday(date) {
                            Text("Today")
                        } else {
                            Text(date, format: .dateTime.weekday(.abbreviated))
                        }
                    }
                }
            }
        }
        .frame(height: 160)
    }
}

struct TodayNumbers: View {
    let chargedWh: Double
    let usedWh: Double
    let onBattery: TimeInterval

    init(day: DaySummary) {
        self.init(chargedWh: day.chargedWh, usedWh: day.usedWh, onBattery: day.onBattery)
    }

    init(week: [DayTotal]) {
        self.init(chargedWh: week.map(\.chargedWh).reduce(0, +), usedWh: week.map(\.usedWh).reduce(0, +), onBattery: week.map(\.onBattery).reduce(0, +))
    }

    init(chargedWh: Double, usedWh: Double, onBattery: TimeInterval) {
        self.chargedWh = chargedWh
        self.usedWh = usedWh
        self.onBattery = onBattery
    }

    var body: some View {
        HStack(spacing: 0) {
            cell("Charged", kWh(chargedWh))
            Divider()
            cell("Used", kWh(usedWh))
            Divider()
            cell("On battery", formatDuration(onBattery / 3600))
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
