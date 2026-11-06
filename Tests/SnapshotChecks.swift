import Foundation

@main
struct SnapshotChecks {
    static func main() {
        var previous = UsageSnapshot.preview
        previous.providers[0].resetCredits = ResetCredits(availableCount: 3, nextExpiresAt: "2026-10-10T10:00:00Z", detailsComplete: true)
        let failed = UsageSnapshot(fetchedAt: "new", providers: [ProviderUsage(name: "Codex", windows: [], error: "Offline")])
        let merged = failed.retainingLastReadings(from: previous)
        assert(merged.providers[0].windows[0].usedPercent == 32)
        assert(merged.providers[0].updatedAt == previous.providers[0].updatedAt)
        assert(merged.providers[0].isStale)
        assert(merged.providers[0].resetCredits?.availableCount == 3)
        let fresh = UsageSnapshot(fetchedAt: "new", providers: [ProviderUsage(name: "Codex", windows: [UsageWindow(label: "Weekly", usedPercent: 0)], updatedAt: "now")])
        assert(fresh.retainingLastReadings(from: previous).providers[0].windows[0].usedPercent == 0)
        assert(UsageWindow.date("2026-10-03T00:10:00.123456+00:00") != nil)
        assert(UsageWindow.date("2026-10-03T00:10:00Z") != nil)
        let now = UsageWindow.date("2026-10-09T12:00:00Z")!
        let reset = "2026-10-13T00:00:00Z"
        let weekly = UsageWindow(label: "Weekly", usedPercent: 65, resetsAt: reset)
        let pace = weekly.weeklyPace(at: now)!
        assert(abs(pace.expectedPercent - 50) < 0.0001)
        assert(pace.points == 15 && pace.symbol == "arrow.up")
        assert(UsageWindow(label: "Sonnet weekly", usedPercent: 35, resetsAt: reset).weeklyPace(at: now)?.symbol == "arrow.down")
        assert(UsageWindow(label: "Weekly", usedPercent: 50.5, resetsAt: reset).weeklyPace(at: now)?.symbol == "circle.fill")
        assert(weekly.weeklyPace(at: weekly.resetDate!) == nil)
        assert(weekly.weeklyPace(at: now.addingTimeInterval(-7 * 86400)) == nil)
        assert(UsageWindow(label: "Weekly", usedPercent: 0).weeklyPace(at: now) == nil)
        assert(UsageWindow(label: "Weekly", usedPercent: 0, resetsAt: "invalid").weeklyPace(at: now) == nil)
        assert(UsageWindow(label: "5 hours", usedPercent: 65, resetsAt: reset).weeklyPace(at: now) == nil)
        assert(weekly.weeklyPace(at: now.addingTimeInterval(86400))!.expectedPercent > pace.expectedPercent)
        var codex = ProviderUsage(name: "Codex", windows: [weekly], resetCredits:
            ResetCredits(availableCount: 2, nextExpiresAt: "2026-10-11T06:00:00Z", detailsComplete: true))
        assert(codex.manualResetDeadline(at: now) != nil)
        assert(abs(codex.pace(for: weekly, at: now)!.expectedPercent - (100 * 3.5 / 5.25)) < 0.0001)
        codex.resetCredits?.availableCount = 0
        assert(codex.manualResetDeadline(at: now) == nil)
        assert(codex.pace(for: weekly, at: now)!.expectedPercent == 50)
        codex.resetCredits?.availableCount = 2
        codex.resetCredits?.nextExpiresAt = reset
        assert(codex.manualResetDeadline(at: now) == nil)
        codex.resetCredits?.nextExpiresAt = "2026-10-08T00:00:00Z"
        assert(codex.manualResetDeadline(at: now) == nil)
        func stamp(_ days: Double) -> String {
            ISO8601DateFormatter().string(from: now.addingTimeInterval(days * 86400))
        }
        let spaced = ResetCredits(availableCount: 2, detailsComplete: true, expiresAt: [stamp(2), stamp(9)])
        assert(spaced.schedulingWarning(at: now) == nil)
        let tight = ResetCredits(availableCount: 2, detailsComplete: true, expiresAt: [stamp(2), stamp(8)])
        let warning = tight.schedulingWarning(at: now)!
        assert(warning.fullWeeksPossible)
        assert(warning.latestFirstUse == now.addingTimeInterval(86400))
        assert(warning.suggestedFirstUse == now.addingTimeInterval(86400 - 3600))
        let impossible = ResetCredits(availableCount: 2, detailsComplete: false, expiresAt: [stamp(1), stamp(3)])
        assert(!impossible.schedulingWarning(at: now)!.fullWeeksPossible)
        assert(impossible.schedulingWarning(at: now)!.suggestedFirstUse == now)
        let chain = ResetCredits(availableCount: 3, detailsComplete: true, expiresAt: [stamp(15), stamp(2), stamp(10)])
        assert(chain.schedulingWarning(at: now)!.latestFirstUse == now.addingTimeInterval(86400))
        let laterPair = ResetCredits(availableCount: 3, detailsComplete: true, expiresAt: [stamp(2), stamp(20), stamp(22)])
        assert(laterPair.schedulingWarning(at: now)!.resetNumber == 2)
        assert(laterPair.schedulingWarning(at: now)!.latestFirstUse == now.addingTimeInterval(15 * 86400))
        let duplicate = ResetCredits(availableCount: 2, detailsComplete: true, expiresAt: [stamp(8), stamp(8)])
        assert(duplicate.schedulingWarning(at: now) != nil)
        assert(ResetCredits(availableCount: 0, detailsComplete: true, expiresAt: [stamp(1), stamp(2)]).schedulingWarning(at: now) == nil)
        assert(ResetCredits(availableCount: 3, detailsComplete: false).schedulingWarning(at: now) == nil)
        let oldJSON = Data(#"{"availableCount":2,"nextExpiresAt":null,"detailsComplete":false}"#.utf8)
        assert(try! JSONDecoder().decode(ResetCredits.self, from: oldJSON).expiresAt == nil)
        print("Snapshot checks passed: stale preservation, reset dates, weekly pace and reset boundaries.")
    }
}
