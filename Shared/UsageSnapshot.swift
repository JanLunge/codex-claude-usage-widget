import Foundation
import OSLog

struct UsageWindow: Codable, Identifiable {
    var label: String
    var usedPercent: Double
    var resetsAt: String?
    var id: String { label }
    var resetDate: Date? { resetsAt.flatMap(Self.date) }
    var isWeekly: Bool { label.lowercased().contains("weekly") }
    func weeklyPace(at now: Date = Date()) -> WeeklyPace? {
        guard isWeekly, usedPercent.isFinite, let reset = resetDate, reset > now else { return nil }
        let week: TimeInterval = 7 * 24 * 60 * 60
        let remaining = reset.timeIntervalSince(now)
        guard remaining <= week else { return nil }
        return WeeklyPace(expectedPercent: (1 - remaining / week) * 100,
                          usedPercent: min(100, max(0, usedPercent)))
    }
    static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
struct WeeklyPace {
    let expectedPercent: Double
    let usedPercent: Double
    var difference: Double { usedPercent - expectedPercent }
    // A one-point tolerance prevents tiny differences from implying action.
    var isOnTrack: Bool { abs(difference) < 1 }
    var symbol: String { isOnTrack ? "circle.fill" : difference > 0 ? "arrow.up" : "arrow.down" }
    var status: String { isOnTrack ? "On track" : difference > 0 ? "Ahead of pace" : "Behind pace" }
    var advice: String { isOnTrack ? "Usage is on track" : difference > 0 ? "Use less to stay on track" : "Room to use more" }
    var points: Int { Int(abs(difference).rounded()) }
    var accessibilityLabel: String {
        "Expected \(Int(expectedPercent.rounded())) percent used by now. \(status)\(isOnTrack ? "" : " by \(points) percentage points"). \(advice)."
    }
}
struct ResetCredits: Codable {
    var availableCount: Int?
    var nextExpiresAt: String?
    var detailsComplete: Bool
    // Optional for compatibility with previously saved usage snapshots.
    var expiresAt: [String]? = nil
    var expiryDate: Date? { nextExpiresAt.flatMap(UsageWindow.date) }
    func schedulingWarning(at now: Date = Date()) -> ResetSchedulingWarning? {
        guard let count = availableCount, count > 1 else { return nil }
        let dates = Array((expiresAt ?? []).compactMap(UsageWindow.date).filter { $0 > now }.sorted().prefix(count))
        guard dates.count > 1 else { return nil }
        let week: TimeInterval = 7 * 86400
        var latestUses = dates
        for index in stride(from: dates.count - 2, through: 0, by: -1) {
            latestUses[index] = min(dates[index], latestUses[index + 1].addingTimeInterval(-week))
        }
        guard let constrained = dates.indices.first(where: { latestUses[$0] < dates[$0] }) else { return nil }
        let latestFirstUse = latestUses[constrained]
        // Leave an hour to act before expiry rather than recommending the expiry instant.
        return ResetSchedulingWarning(resetNumber: constrained + 1, latestFirstUse: latestFirstUse,
                                      suggestedFirstUse: max(now, latestFirstUse.addingTimeInterval(-3600)),
                                      fullWeeksPossible: latestFirstUse > now,
                                      detailsComplete: detailsComplete)
    }
}
struct ResetSchedulingWarning {
    let resetNumber: Int
    let latestFirstUse: Date
    let suggestedFirstUse: Date
    let fullWeeksPossible: Bool
    let detailsComplete: Bool
    var explanation: String {
        "Later reset credits expire less than seven days apart. " +
        (fullWeeksPossible ? "Use reset \(resetNumber) early to leave seven days for each following reset. Suggestion includes a one-hour buffer." :
         "Even starting now cannot leave seven full days for every listed reset; use the first now and plan to use the next before its expiry.") +
        (detailsComplete ? "" : " Based on listed credits; other expiry details are unavailable.")
    }

}
struct ProviderUsage: Codable, Identifiable {
    var name: String
    var windows: [UsageWindow]
    var updatedAt: String?
    var error: String?
    var resetCredits: ResetCredits? = nil
    var id: String { name }
    // A usable credit expiring before the weekly reset becomes the usage deadline.
    func manualResetDeadline(at now: Date = Date()) -> Date? {
        guard name == "Codex", let credits = resetCredits,
              let count = credits.availableCount, count > 0,
              let expiry = credits.expiryDate, expiry > now,
              let weeklyReset = windows.first(where: { $0.isWeekly })?.resetDate,
              expiry < weeklyReset else { return nil }
        return expiry
    }
    func pace(for window: UsageWindow, at now: Date = Date()) -> WeeklyPace? {
        guard let normal = window.weeklyPace(at: now),
              let deadline = manualResetDeadline(at: now), let reset = window.resetDate else {
            return window.weeklyPace(at: now)
        }
        let start = reset.addingTimeInterval(-7 * 86400)
        guard deadline > start else { return normal }
        return WeeklyPace(expectedPercent: min(100, max(0, now.timeIntervalSince(start) / deadline.timeIntervalSince(start) * 100)),
                          usedPercent: normal.usedPercent)
    }
    var updateDate: Date? { updatedAt.flatMap(UsageWindow.date) }
    var isStale: Bool { error != nil || updateDate.map { Date().timeIntervalSince($0) > 900 } ?? true }
}
struct UsageSnapshot: Codable {
    var fetchedAt: String
    var providers: [ProviderUsage]
    static let empty = UsageSnapshot(fetchedAt: "", providers: [
        ProviderUsage(name: "Codex", windows: [], error: "Open Usage Widget to connect."),
        ProviderUsage(name: "Claude Code", windows: [], error: "Open Usage Widget to connect.")
    ])
    static let preview = UsageSnapshot(fetchedAt: "", providers: [
        ProviderUsage(name: "Codex", windows: [UsageWindow(label: "5 hours", usedPercent: 32), UsageWindow(label: "Weekly", usedPercent: 58)], updatedAt: ISO8601DateFormatter().string(from: Date())),
        ProviderUsage(name: "Claude Code", windows: [UsageWindow(label: "5 hours", usedPercent: 18), UsageWindow(label: "Weekly", usedPercent: 41)], updatedAt: ISO8601DateFormatter().string(from: Date()))
    ])
    func retainingLastReadings(from previous: UsageSnapshot) -> UsageSnapshot {
        var merged = self
        for index in merged.providers.indices where merged.providers[index].error != nil {
            if let old = previous.providers.first(where: { $0.name == merged.providers[index].name }) {
                merged.providers[index].windows = old.windows
                merged.providers[index].updatedAt = old.updatedAt
                merged.providers[index].resetCredits = old.resetCredits
            }
        }
        return merged
    }
}
enum SnapshotStore {
    private static let logger = Logger(subsystem: "com.janlunge.usagewidget", category: "cache")
    static let widgetBundleIdentifier = "com.janlunge.usagewidget.widget"
    static var url: URL {
        // Local ad hoc signing cannot authorize a provisioned app group. The
        // unsandboxed containing app publishes only usage to its own extension's
        // container; the sandboxed widget reads its ordinary Application Support.
        #if WIDGET_EXTENSION
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #else
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(widgetBundleIdentifier)/Data/Library/Application Support")
        #endif
        return support.appendingPathComponent("UsageWidget/usage.json")
    }
    static func load() -> UsageSnapshot {
        do {
            let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: url))
            logger.info("Usage cache loaded; providers=\(snapshot.providers.count) windows=\(snapshot.providers.reduce(0) { $0 + $1.windows.count })")
            return snapshot
        } catch {
            let failure = error as NSError
            logger.error("Usage cache read failed: domain=\(failure.domain, privacy: .public) code=\(failure.code) path=\(url.path, privacy: .public)")
            #if !WIDGET_EXTENSION
            // Migrate the old usage-only cache so the app retains readings during
            // its first refresh after this update. The widget never accesses it.
            let legacy = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.janlunge.usagewidget/usage.json")
            if let data = try? Data(contentsOf: legacy),
               let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
                return snapshot
            }
            #endif
            return .empty
        }
    }
    static func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
