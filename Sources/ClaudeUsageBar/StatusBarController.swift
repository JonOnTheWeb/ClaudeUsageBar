import AppKit

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let api = UsageAPI()
    private var timer: Timer?

    // UI-level poll cadence. UsageAPI enforces its own floor underneath
    // this, so tightening this further won't hammer the endpoint any harder.
    private let pollInterval: TimeInterval = 60

    override init() {
        super.init()
        statusItem.button?.title = "Claude ⋯"
        buildMenu(sessionText: "Loading…", weeklyText: "Loading…", errorText: nil)
        startPolling()
    }

    private func startPolling() {
        Task { await self.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private func refresh() async {
        do {
            let snapshot = try await api.fetchUsage()
            render(snapshot)
        } catch {
            renderError(error)
        }
    }

    private func render(_ snapshot: UsageSnapshot) {
        let sessionPct = snapshot.sessionUsedPercent.map { "\(Int($0.rounded()))%" } ?? "?"
        let weeklyPct = snapshot.weeklyUsedPercent.map { "\(Int($0.rounded()))%" } ?? "?"

        statusItem.button?.title = "S \(sessionPct) · W \(weeklyPct)"

        let sessionDetail = detailLine(label: "Session", percent: snapshot.sessionUsedPercent, resetsAt: snapshot.sessionResetsAt)
        let weeklyDetail = detailLine(label: "Weekly", percent: snapshot.weeklyUsedPercent, resetsAt: snapshot.weeklyResetsAt)

        buildMenu(sessionText: sessionDetail, weeklyText: weeklyDetail, errorText: nil)
    }

    private func detailLine(label: String, percent: Double?, resetsAt: Date?) -> String {
        var parts: [String] = []
        parts.append(percent.map { "\(Int($0.rounded()))% used" } ?? "unknown — check CLAUDE_USAGE_DEBUG output")
        if let resetsAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            parts.append("resets \(formatter.localizedString(for: resetsAt, relativeTo: Date()))")
        }
        return "\(label): \(parts.joined(separator: ", "))"
    }

    private func renderError(_ error: Error) {
        statusItem.button?.title = "Claude ⚠️"
        buildMenu(sessionText: "", weeklyText: "", errorText: error.localizedDescription)
    }

    private func buildMenu(sessionText: String, weeklyText: String, errorText: String?) {
        let menu = NSMenu()

        if let errorText {
            menu.addItem(withTitle: errorText, action: nil, keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
        } else {
            menu.addItem(withTitle: sessionText, action: nil, keyEquivalent: "")
            menu.addItem(withTitle: weeklyText, action: nil, keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func refreshNow() {
        Task { await self.refresh() }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
