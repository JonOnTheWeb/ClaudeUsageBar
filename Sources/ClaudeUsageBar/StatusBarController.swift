import AppKit

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    /// How often the UI asks for fresh data. The numbers move slowly and
    /// opening the menu refreshes on demand, so this can be relaxed.
    /// `UsageAPI.minimumPollInterval` is the floor underneath, so lowering
    /// this alone won't hit the endpoint any harder.
    private let pollInterval: TimeInterval = 300

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let api = UsageAPI()
    private let sessionItem = NSMenuItem()
    private let weeklyItem = NSMenuItem()
    private let errorItem = NSMenuItem()

    private var snapshot: UsageSnapshot?
    private var lastError: Error?
    private var timer: Timer?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    override init() {
        super.init()
        statusItem.button?.title = "Claude ⋯"
        statusItem.menu = makeMenu()
        render()

        timer = Timer.scheduledTimer(timeInterval: pollInterval, target: self,
                                     selector: #selector(refreshNow), userInfo: nil, repeats: true)
        refreshNow()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(sessionItem)
        menu.addItem(weeklyItem)
        menu.addItem(errorItem)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    // MARK: - Refreshing

    @objc private func refreshNow() {
        Task { await refresh() }
    }

    private func refresh() async {
        do {
            snapshot = try await api.fetchUsage()
            lastError = nil
        } catch {
            lastError = error
        }
        render()
    }

    /// Re-render on open so the "resets in…" countdowns are current, and
    /// kick a refresh while we're at it. `UsageAPI`'s floor keeps that cheap.
    func menuWillOpen(_ menu: NSMenu) {
        render()
        refreshNow()
    }

    // MARK: - Rendering

    /// The last good numbers stay in the menu bar through a failed poll
    /// (sleep/wake, offline, a 5xx). The item is greyed out rather than
    /// retitled: a width change can push it off a crowded menu bar, which
    /// notch Macs do silently, and the menu already shows the error.
    private func render() {
        if let snapshot {
            statusItem.button?.title =
                "S \(percentText(snapshot.session?.percent)) · W \(percentText(snapshot.weekly?.percent))"
        } else if lastError != nil {
            statusItem.button?.title = "Claude ⚠️"
        }
        statusItem.button?.appearsDisabled = lastError != nil

        sessionItem.title = detailLine("Session", snapshot?.session)
        weeklyItem.title = detailLine("Weekly", snapshot?.weekly)
        errorItem.title = lastError.map { "⚠️ \($0.localizedDescription)" } ?? ""
        errorItem.isHidden = lastError == nil
    }

    private func detailLine(_ label: String, _ limit: UsageSnapshot.Limit?) -> String {
        guard let limit else { return "\(label): –" }
        var line = "\(label): \(percentText(limit.percent)) used"
        if let resetsAt = limit.resetsAt {
            line += ", resets \(Self.relativeFormatter.localizedString(for: resetsAt, relativeTo: Date()))"
        }
        return line
    }

    private func percentText(_ percent: Double?) -> String {
        percent.map { "\(Int($0.rounded()))%" } ?? "?"
    }
}
