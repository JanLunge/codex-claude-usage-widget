import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot
}
struct UsageTimeline: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { UsageEntry(date: Date(), snapshot: .preview) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: context.isPreview ? .preview : SnapshotStore.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [UsageEntry(date: now, snapshot: SnapshotStore.load())],
                            policy: .after(now.addingTimeInterval(300))))
    }
}
struct UsageWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry
    var body: some View {
        Group {
            if family == .systemMedium {
                UsageBands(snapshot: entry.snapshot)
            } else {
                UsageDashboard(snapshot: entry.snapshot, compact: family == .systemSmall, dense: true,
                               vertical: true, maxWindows: family == .systemSmall ? 1 : 4)
                    .padding(16)
            }
        }
            .containerBackground(for: .widget) { Color(red: 0.065, green: 0.078, blue: 0.082) }
            .widgetURL(URL(string: "usagewidget://dashboard"))
    }
}
@main
struct AccountUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AccountUsageWidget", provider: UsageTimeline()) { entry in
            UsageWidgetView(entry: entry)
        }.configurationDisplayName("Usage Widget")
            .description("Codex and Claude Code usage from this Mac’s signed-in accounts.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
            .contentMarginsDisabled()
    }
}
