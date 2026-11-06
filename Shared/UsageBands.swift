import SwiftUI

/// Horizon: equal usage bands joined by a shared reset and credit timeline.
struct UsageBands: View {
    let snapshot: UsageSnapshot
    private var codex: ProviderUsage? { snapshot.providers.first { $0.name == "Codex" } }
    var body: some View {
        GeometryReader { geometry in
            let providers = snapshot.providers
            let bandHeight = max(0, (geometry.size.height - 48) / CGFloat(max(1, providers.count)))
            VStack(spacing: 0) {
                ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                    HorizonUsageBand(provider: provider).frame(height: bandHeight)
                    if index == 0 {
                        HorizonResetTimeline(providers: providers, credits: codex?.resetCredits).frame(height: 48)
                    }
                }
                if providers.isEmpty {
                    Text("Open Usage Widget to connect").font(.caption).foregroundStyle(.white.opacity(0.7))
                }
            }
        }.background(Color(red: 0.025, green: 0.03, blue: 0.045))
            .environment(\.colorScheme, .dark)
    }
}

private struct HorizonUsageBand: View {
    let provider: ProviderUsage
    private var window: UsageWindow? { provider.windows.first(where: { $0.isWeekly }) ?? provider.windows.first }
    private var pace: WeeklyPace? { window.flatMap { provider.pace(for: $0) } }
    private var isCodex: Bool { provider.name == "Codex" }
    private var name: String { provider.name == "Claude Code" ? "Claude" : provider.name }
    private var fillColors: [Color] {
        isCodex ? [Color(red: 0.05, green: 0.18, blue: 0.51), Color(red: 0.12, green: 0.39, blue: 0.9), Color(red: 0.25, green: 0.59, blue: 1)] :
            [Color(red: 0.43, green: 0.15, blue: 0.06), Color(red: 0.81, green: 0.35, blue: 0.19), Color(red: 0.97, green: 0.54, blue: 0.37)]
    }
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let used = min(100, max(0, window?.usedPercent ?? 0)) / 100
            ZStack(alignment: .leading) {
                (isCodex ? Color(red: 0.04, green: 0.055, blue: 0.095) : Color(red: 0.08, green: 0.045, blue: 0.035))
                LinearGradient(colors: fillColors, startPoint: .leading, endPoint: .trailing)
                    .frame(width: width * used)
                if window != nil {
                    Rectangle().fill(.white.opacity(0.6)).frame(width: 0.75)
                        .offset(x: max(0, width * used - 0.75))
                }
                if let pace {
                    let target = min(1, max(0, pace.expectedPercent / 100))
                    HorizonHatching(color: pace.difference > 0 ? .orange : Color(red: 0.49, green: 0.89, blue: 0.63))
                        .frame(width: width * abs(target - used))
                        .offset(x: width * min(used, target))
                    Rectangle().fill(.white).frame(width: 1.5)
                        .shadow(color: .white.opacity(0.5), radius: 3)
                        .offset(x: min(width - 1.5, width * target))
                }
                HStack(spacing: 4) {
                    VStack(spacing: 3) {
                        ProviderIcon(provider: provider, size: 18)
                        Text(name).font(.system(size: 9, weight: .medium))
                    }.frame(width: 33)
                    if let window {
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(Int(window.usedPercent.rounded()))")
                                .font(.system(size: 38, weight: .light, design: .rounded)).tracking(-1.5)
                            Text("%").font(.system(size: 16, weight: .light)).foregroundStyle(.white.opacity(0.8))
                        }.monospacedDigit()
                    } else {
                        Text("—").font(.system(size: 32, weight: .light))
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 5) {
                        if let pace {
                            HStack(spacing: 3) {
                                Text("\(pace.difference > 0 ? "+" : pace.isOnTrack ? "" : "−")\(pace.points) pp")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(pace.isOnTrack ? Color.white : pace.difference > 0 ? Color.orange : Color(red: 0.49, green: 0.89, blue: 0.63))
                                Text("· \(provider.manualResetDeadline() != nil ? "reset target" : "target") \(Int(pace.expectedPercent.rounded()))")
                                    .foregroundStyle(.white.opacity(0.7))
                            }.font(.system(size: 10))
                        }
                        if let date = window?.resetDate {
                            HStack(spacing: 3) {
                                Image(systemName: isCodex ? "triangle.fill" : "arrowtriangle.down.fill")
                                    .font(.system(size: 5)).foregroundStyle(provider.accent)
                                Text("Weekly reset \(HorizonTime.remaining(until: date))")
                            }.font(.system(size: 9.5, weight: .medium))
                        } else {
                            Text(window == nil ? "Usage unavailable" : "Reset time unavailable")
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.65))
                        }
                        if provider.isStale {
                            Label("Stale reading", systemImage: "clock.badge.exclamationmark")
                                .font(.system(size: 8)).foregroundStyle(.orange)
                        }
                    }.lineLimit(1).minimumScaleFactor(0.75)
                        .padding(4)
                        .background(.black.opacity(used > 0.65 ? 0.45 : 0), in: RoundedRectangle(cornerRadius: 4))
                }.padding(.horizontal, 13).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }.clipped()
        }.accessibilityElement(children: .combine)
            .accessibilityLabel("\(name), \(window.map { "\(Int($0.usedPercent.rounded())) percent used" } ?? "usage unavailable")")
            .accessibilityValue(pace?.accessibilityLabel ?? "")
    }
}

private struct HorizonHatching: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: -size.height, through: size.width, by: 4) {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
            }
            context.stroke(path, with: .color(color.opacity(0.35)), lineWidth: 0.7)
        }.clipped().accessibilityHidden(true)
    }
}

private struct HorizonResetTimeline: View {
    let providers: [ProviderUsage]
    let credits: ResetCredits?
    private var warning: ResetSchedulingWarning? { credits?.schedulingWarning() }
    private var expiries: [Date] {
        guard let count = credits?.availableCount, count > 0 else { return [] }
        let dates = (credits?.expiresAt ?? []).compactMap(UsageWindow.date).sorted()
        return Array((dates.isEmpty ? credits?.expiryDate.map { [$0] } ?? [] : dates).prefix(count))
    }
    private var laterExpiries: String {
        expiries.enumerated().dropFirst().prefix(2).map { index, date in
            "#\(index + 1) \(date.formatted(.dateTime.month(.abbreviated).day()))"
        }.joined(separator: " · ")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(credits?.availableCount.map { "\($0) manual resets" } ?? "Manual resets unavailable")
                    .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                Spacer(minLength: 0)
                if let warning {
                    Label(warning.fullWeeksPossible ? "Use #\(warning.resetNumber) by \(warning.suggestedFirstUse.formatted(.dateTime.month(.abbreviated).day().hour().minute()))" : "Use #1 now · next expires early",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.37, blue: 0.34))
                        .help(warning.explanation)
                }
            }.lineLimit(1).minimumScaleFactor(0.75).frame(height: 16)
            axis.frame(height: 15)
            HStack(spacing: 2) {
                Image(systemName: "hourglass").font(.system(size: 8))
                if let date = credits?.expiryDate, credits?.availableCount != 0 {
                    Text("\(credits?.detailsComplete == true ? "#1 expires" : "Listed expiry") \(HorizonTime.remaining(until: date))")
                        .fontWeight(.semibold)
                } else {
                    Text(credits?.availableCount == 0 ? "No resets left" : credits?.detailsComplete == true ? "No expiry" : "Expiry unavailable")
                }
                Spacer(minLength: 2)
                if !laterExpiries.isEmpty {
                    Text("Expiry \(laterExpiries)").foregroundStyle(.white.opacity(0.6))
                }
            }.font(.system(size: 8.5)).foregroundStyle(Color(red: 1, green: 0.72, blue: 0.31))
                .lineLimit(1).minimumScaleFactor(0.7).frame(height: 15)
        }.padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.045, green: 0.045, blue: 0.055))
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5) }
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.18)).frame(height: 0.5) }
            .accessibilityElement(children: .combine)
    }
    private var axis: some View {
        Canvas { context, size in
            let now = Date()
            let resets = providers.compactMap { provider -> (ProviderUsage, Date)? in
                guard let date = provider.windows.first(where: { $0.isWeekly })?.resetDate, date > now else { return nil }
                return (provider, date)
            }
            let dates = expiries + resets.map { $0.1 } + (warning.map { [$0.suggestedFirstUse] } ?? [])
            let duration = max(7 * 86400, dates.map { $0.timeIntervalSince(now) }.max() ?? 0)
            let inset: CGFloat = 3
            func x(_ date: Date) -> CGFloat {
                inset + (size.width - 2 * inset) * min(1, max(0, date.timeIntervalSince(now) / duration))
            }
            let mid = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: inset, y: mid))
            line.addLine(to: CGPoint(x: size.width - inset, y: mid))
            context.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
            if let warning, let expiry = expiries.dropFirst(warning.resetNumber - 1).first {
                let start = x(warning.suggestedFirstUse)
                let end = x(expiry)
                context.fill(Path(CGRect(x: start, y: mid - 2, width: max(0, end - start), height: 4)), with: .color(.red.opacity(0.65)))
                context.fill(Path(CGRect(x: start, y: mid - 6, width: 1, height: 12)), with: .color(.red))
            }
            for (provider, date) in resets {
                let px = x(date)
                let up = provider.name == "Codex"
                let tip = up ? mid - 7 : mid + 7
                let base = up ? mid - 2 : mid + 2
                var triangle = Path()
                triangle.move(to: CGPoint(x: px, y: tip))
                triangle.addLine(to: CGPoint(x: px - 3, y: base))
                triangle.addLine(to: CGPoint(x: px + 3, y: base))
                triangle.closeSubpath()
                context.fill(triangle, with: .color(provider.accent))
            }
            context.fill(Path(ellipseIn: CGRect(x: 0, y: mid - 2.5, width: 5, height: 5)), with: .color(.white))
            for (index, date) in expiries.enumerated() {
                let px = min(size.width - 6, max(6, x(date)))
                let color: Color = index == 0 ? .orange : warning?.resetNumber == index + 1 ? .red : Color(white: 0.25)
                let rect = CGRect(x: px - 6, y: mid - 6, width: 12, height: 12)
                context.fill(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(Color(red: 0.045, green: 0.045, blue: 0.055)))
                context.fill(Path(ellipseIn: rect), with: .color(color))
                context.draw(Text("\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundColor(index == 0 ? .black : .white), at: CGPoint(x: px, y: mid))
            }
        }.accessibilityHidden(true)
    }
}

private enum HorizonTime {
    static func remaining(until date: Date, at now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        guard seconds > 0 else { return "now" }
        let hours = seconds / 3600
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \((seconds % 3600) / 60)m" }
        return "\(max(1, seconds / 60))m"
    }
}
