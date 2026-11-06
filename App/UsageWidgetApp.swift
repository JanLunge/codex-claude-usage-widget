import AppKit
import SwiftUI
import WidgetKit
import ServiceManagement

@MainActor
final class UsageModel: ObservableObject {
    @Published var snapshot = SnapshotStore.load()
    @Published var refreshing = false
    @Published var storageError: String?
    private var timer: Timer?
    private var lastAttempt: Date?
    init() {
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }
    func refresh() async {
        guard !refreshing, lastAttempt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true else { return }
        refreshing = true
        lastAttempt = Date()
        defer { refreshing = false }
        guard let script = Bundle.main.url(forResource: "usage", withExtension: "py") else {
            storageError = "Usage helper is missing. Rebuild the app."
            return
        }
        let result = await Task.detached { () -> UsageSnapshot? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                return try JSONDecoder().decode(UsageSnapshot.self, from: data)
            } catch { return nil }
        }.value
        guard let result else {
            storageError = "The usage helper could not run. Check the installed Python runtime."
            return
        }
        snapshot = result.retainingLastReadings(from: snapshot)
        do {
            try SnapshotStore.save(snapshot)
            storageError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch { storageError = "The widget cache could not be saved to its protected container." }
    }
}
struct DashboardWindow: View {
    @ObservedObject var model: UsageModel
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Usage Widget").font(.system(size: 28, weight: .semibold))
                    Text("Your coding accounts, at a glance.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
                }.disabled(model.refreshing).help("Refresh usage (at most once a minute)")
            }
            UsageDashboard(snapshot: model.snapshot, vertical: true, maxWindows: 4)
                .padding(24).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
            HStack(spacing: 5) {
                Circle().fill(model.refreshing ? Color.orange : Color.green).frame(width: 5, height: 5)
                if model.refreshing { Text("Refreshing accounts…") }
                else if let date = UsageWindow.date(model.snapshot.fetchedAt) {
                    Text("Last checked")
                    Text(date, style: .relative)
                    Text("ago · refreshes every 5 minutes")
                } else { Text("Waiting for first reading") }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if let error = model.storageError ?? loginError { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            HStack {
                Toggle("Open at login", isOn: $launchAtLogin).toggleStyle(.switch).controlSize(.small)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch { loginError = "Login setting could not be changed. Check System Settings → Login Items." }
                    }
                Spacer()
                Text("Right-click desktop → Edit Widgets → Usage Widget")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("Reuses local sign-ins. Only usage readings are saved to the widget cache. Keep this app running for automatic refresh.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 560).background(Color(red: 0.065, green: 0.078, blue: 0.082))
            .preferredColorScheme(.dark)
    }
}
struct MenuPanel: View {
    @ObservedObject var model: UsageModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            UsageDashboard(snapshot: model.snapshot)
            Divider()
            HStack {
                Button("Open dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.refreshing)
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
            }.buttonStyle(.borderless).font(.caption)
        }.padding(20).frame(width: 380).preferredColorScheme(.dark)
    }
}
@main
struct UsageWidgetApp: App {
    @StateObject private var model = UsageModel()
    var body: some Scene {
        Window("Usage Widget", id: "dashboard") {
            DashboardWindow(model: model)
                .onOpenURL { _ in Task { await model.refresh() } }
        }.windowResizability(.contentSize)
        MenuBarExtra("Usage Widget", systemImage: "chart.bar.xaxis") {
            MenuPanel(model: model)
        }.menuBarExtraStyle(.window)
    }
}
