import SwiftUI

extension ProviderUsage {
    var accent: Color { name == "Codex" ? Color(red: 0.32, green: 0.63, blue: 1.0) : Color(red: 0.96, green: 0.62, blue: 0.46) }
    var symbol: String { name == "Codex" ? "terminal" : "sparkle" }
}
struct UsageMeter: View {
    let window: UsageWindow
    let accent: Color
    var compact = false
    var dense = false
    var provider: ProviderUsage? = nil
    private var pace: WeeklyPace? { provider?.pace(for: window) ?? window.weeklyPace() }
    var body: some View {
        VStack(alignment: .leading, spacing: compact || dense ? 2 : 7) {
            if !compact {
                HStack {
                    Text(window.label).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(window.usedPercent.rounded()))% used").monospacedDigit().fontWeight(.medium)
                    if let pace { WeeklyPaceBadge(pace: pace) }
                }.font(.system(size: compact || dense ? 10 : 12))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.13))
                        .frame(height: compact || dense ? 4 : 6)
                    Capsule().fill(window.usedPercent >= 90 ? Color.orange : accent)
                        .frame(width: geometry.size.width * min(1, max(0, window.usedPercent / 100)))
                        .frame(height: compact || dense ? 4 : 6)
                    if let pace {
                        Rectangle().fill(Color.primary.opacity(0.85)).frame(width: 2, height: 10)
                            .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * pace.expectedPercent / 100)))
                    }
                }
                .frame(height: 10)
            }.frame(height: 10)
            if let pace {
                Text(compact ? "Usage target \(Int(pace.expectedPercent.rounded()))%" : "Target now \(Int(pace.expectedPercent.rounded()))% · \(pace.advice)")
                    .font(.system(size: compact || dense ? 9 : 11)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            if let reset = window.resetDate {
                DeadlineCountdown(date: reset, label: "Resets in", reached: "Reset reached", compact: compact || dense)
            }
        }.accessibilityElement(children: .combine)
    }
}
struct WeeklyPaceBadge: View {
    let pace: WeeklyPace
    var compact = false
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: pace.symbol).font(.system(size: pace.isOnTrack ? 4 : 9, weight: .bold))
            if !pace.isOnTrack { Text("\(pace.points)\(compact ? "" : "pp")").monospacedDigit() }
        }.font(.system(size: 9, weight: .medium))
            .foregroundStyle(pace.isOnTrack ? Color.secondary : pace.difference > 0 ? Color.orange : Color.green)
            .fixedSize()
            .help(pace.accessibilityLabel)
            .accessibilityElement(children: .ignore).accessibilityLabel(pace.accessibilityLabel)
    }
}
struct ProviderCard: View {
    let provider: ProviderUsage
    var compact = false
    var dense = false
    var maxWindows = 2
    private var visibleWindows: [UsageWindow] {
        compact ? Array((compactSummary.map { [$0] } ?? []).prefix(maxWindows)) : Array(provider.windows.prefix(maxWindows))
    }
    private var compactSummary: UsageWindow? {
        provider.windows.first(where: { $0.isWeekly }) ?? provider.windows.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : dense ? 5 : 15) {
            HStack(spacing: 7) {
                ProviderIcon(provider: provider, size: compact ? 14 : dense ? 18 : 20)
                Text(compact && provider.name == "Claude Code" ? "Claude" : provider.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(provider.name == "Codex" ? provider.accent : Color.primary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if compact, let window = compactSummary {
                    Text("\(Int(window.usedPercent.rounded()))%")
                        .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    if let pace = provider.pace(for: window) { WeeklyPaceBadge(pace: pace, compact: true) }
                }
                if provider.isStale {
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                        .accessibilityLabel("Stale or unavailable")
                }
            }.font(.system(size: compact ? 12 : dense ? 13 : 15))
            if provider.windows.isEmpty {
                Text(provider.error ?? "Usage unavailable").font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(visibleWindows) { window in
                    UsageMeter(window: window, accent: provider.accent, compact: compact, dense: dense, provider: provider)
                }
                if let credits = provider.resetCredits {
                    ResetCreditsView(credits: credits, accent: provider.accent, compact: compact || dense, highlighted: provider.manualResetDeadline() != nil)
                }
                if provider.isStale && !compact && !dense {
                    Text(provider.error ?? "Open app to refresh stale readings")
                        .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
struct DeadlineCountdown: View {
    let date: Date
    let label: String
    let reached: String
    var compact = false
    var body: some View {
        HStack(spacing: 3) {
            if date > Date() {
                Text(label)
                Text(date, style: .relative).monospacedDigit()
            } else {
                Text(reached + " · refresh pending")
            }
        }.font(.system(size: compact ? 9 : 11))
            .foregroundStyle(date > Date() ? Color.secondary : Color.orange)
            .lineLimit(1).minimumScaleFactor(0.75)
            .accessibilityElement(children: .combine)
    }
}
struct ResetCreditsView: View {
    let credits: ResetCredits
    let accent: Color
    var compact = false
    var highlighted = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(accent)
                if let count = credits.availableCount {
                    Text("\(count) \(count == 1 ? "reset" : "resets") left").fontWeight(.medium)
                } else {
                    Text("Reset count unavailable").foregroundStyle(.secondary)
                }
            }.font(.system(size: compact ? 11 : 13))
            if let expiry = credits.expiryDate {
                DeadlineCountdown(date: expiry, label: highlighted ? "Use before" : credits.detailsComplete ? "Expires in" : "Listed expiry in",
                                  reached: "Expiry reached", compact: compact)
                if !compact {
                    Text(expiry, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else if let count = credits.availableCount, count > 0 {
                Text(credits.detailsComplete ? "No expiry" : "Expiry unavailable")
                    .font(.system(size: compact ? 9 : 11)).foregroundStyle(.secondary)
            }
            if let warning = credits.schedulingWarning() {
                ResetScheduleWarningView(warning: warning)
            }
        }.padding(highlighted ? 4 : 0)
            .background(highlighted ? Color.orange.opacity(0.18) : Color.clear)
            .accessibilityElement(children: .combine)
    }
}
struct ResetScheduleWarningView: View {
    let warning: ResetSchedulingWarning
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
            if warning.fullWeeksPossible {
                Text("\(warning.detailsComplete ? "Use #\(warning.resetNumber) by" : "Listed: #\(warning.resetNumber) by") \(warning.suggestedFirstUse.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · next expires early")
            } else {
                Text("Use first now · next reset has less than 7d")
            }
        }.font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.red).lineLimit(2).minimumScaleFactor(0.8)
            .help(warning.explanation)
            .accessibilityElement(children: .combine)
            .accessibilityHint(warning.explanation)
    }
}
struct UsageDashboard: View {
    let snapshot: UsageSnapshot
    var compact = false
    var dense = false
    var vertical = false
    var maxWindows = 2
    var body: some View {
        VStack(alignment: .leading, spacing: compact || dense ? 5 : 20) {
            if !compact && !dense {
                HStack {
                    Text("ACCOUNT USAGE").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                    Spacer()
                    Text("THIS MAC").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1)
                }.foregroundStyle(.secondary)
            }
            if vertical {
                VStack(spacing: compact || dense ? 5 : 20) {
                    ForEach(snapshot.providers) { provider in
                        ProviderCard(provider: provider, compact: compact, dense: dense, maxWindows: maxWindows)
                        if provider.id != snapshot.providers.last?.id { Divider() }
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(snapshot.providers) { provider in
                        ProviderCard(provider: provider, dense: dense, maxWindows: maxWindows)
                        if provider.id != snapshot.providers.last?.id { Divider() }
                    }
                }
            }
        }
    }
}
