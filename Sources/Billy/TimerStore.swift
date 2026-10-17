import Foundation
import Observation

struct Entry: Codable, Identifiable, Equatable {
    /// Keeps a description to one line.
    static let maxTitleLength = 45

    var id = UUID()
    var title: String
    var duration: TimeInterval
    var endedAt: Date
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var entries: [Entry] = []

    var total: TimeInterval { entries.total }
    var lastActive: Date? { entries.map(\.endedAt).max() }
}

struct BillingSettings: Codable, Equatable {
    var hourlyRate: Double = 0
    var vatPercent: Double = 24
    var currency = "kr"

    var hasRate: Bool { hourlyRate > 0 }

    func bill(_ duration: TimeInterval) -> Billing {
        Billing(duration: duration, rate: hourlyRate, vatPercent: vatPercent)
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BillingSettings()
        hourlyRate = try c.decodeIfPresent(Double.self, forKey: .hourlyRate) ?? d.hourlyRate
        vatPercent = try c.decodeIfPresent(Double.self, forKey: .vatPercent) ?? d.vatPercent
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? d.currency
    }
}

struct Billing {
    let duration: TimeInterval
    let rate: Double
    let vatPercent: Double

    var hours: Double { duration / 3600 }
    /// Without VSK.
    var net: Double { hours * rate }
    var vat: Double { net * vatPercent / 100 }
    /// With VSK.
    var gross: Double { net + vat }
}

extension Array where Element == Entry {
    var total: TimeInterval { reduce(0) { $0 + $1.duration } }
}

@Observable
@MainActor
final class TimerStore {
    private(set) var entries: [Entry] = []
    private(set) var accumulated: TimeInterval = 0
    private(set) var startedAt: Date?
    /// Set while a finished entry is waiting for its title.
    private(set) var pendingEntry: TimeInterval?
    private(set) var projects: [Project] = []
    /// Set while the session is waiting to be filed into a project; holds the unlogged time.
    private(set) var pendingFinish: TimeInterval?
    var settings = BillingSettings() { didSet { save() } }
    @ObservationIgnored private var resumeOnCancel = false

    var isRunning: Bool { startedAt != nil }
    var total: TimeInterval { entries.total }
    var isPending: Bool { pendingEntry != nil || pendingFinish != nil }

    /// Most recently worked-on first.
    var projectsByRecent: [Project] {
        projects.sorted { ($0.lastActive ?? .distantPast) > ($1.lastActive ?? .distantPast) }
    }

    func project(_ id: Project.ID) -> Project? { projects.first { $0.id == id } }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (startedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    init() { load() }

    // MARK: Timer

    func toggle() {
        guard !isPending else { return }
        if let startedAt {
            accumulated += Date.now.timeIntervalSince(startedAt)
            self.startedAt = nil
        } else {
            startedAt = .now
        }
        save()
    }

    func resetTimer() {
        guard !isPending else { return }
        accumulated = 0
        startedAt = nil
        save()
    }

    // MARK: Entries

    /// Stops the clock and waits for a title.
    func log() {
        guard !isPending else { return }
        let elapsed = elapsed()
        guard elapsed >= 1 else { return }
        resumeOnCancel = isRunning
        accumulated = elapsed
        startedAt = nil
        pendingEntry = elapsed
        save()
    }

    func commitEntry(title: String) {
        guard let duration = pendingEntry else { return }
        entries.append(Entry(title: Self.title(title), duration: duration, endedAt: .now))
        pendingEntry = nil
        accumulated = 0
        startedAt = .now
        save()
    }

    /// Logs part of the time waiting for a title as its own entry; the rest keeps waiting.
    func splitPending(title: String, duration: TimeInterval) {
        guard let pending = pendingEntry, duration >= 1, pending - duration >= 1 else { return }
        entries.append(Entry(title: Self.title(title), duration: duration, endedAt: .now))
        pendingEntry = pending - duration
        accumulated = pending - duration
        save()
    }

    /// Like `splitPending`, for the unlogged time while finishing.
    func splitUnlogged(title: String, duration: TimeInterval) {
        guard let unlogged = pendingFinish, duration >= 1, unlogged - duration >= 1 else { return }
        entries.append(Entry(title: Self.title(title), duration: duration, endedAt: .now))
        pendingFinish = unlogged - duration
        accumulated = unlogged - duration
        save()
    }

    /// Discards the entry and puts the clock back the way it was.
    func cancelEntry() {
        guard pendingEntry != nil else { return }
        pendingEntry = nil
        if resumeOnCancel { startedAt = .now }
        save()
    }

    /// Renames an entry, whether it's in the current session or already filed into a project.
    func rename(_ id: Entry.ID, to title: String) {
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Entry.maxTitleLength))
        guard !trimmed.isEmpty else { return }
        if let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].title = trimmed
        } else {
            for p in projects.indices {
                if let i = projects[p].entries.firstIndex(where: { $0.id == id }) {
                    projects[p].entries[i].title = trimmed
                }
            }
        }
        save()
    }

    func delete(_ id: Entry.ID) {
        entries.removeAll { $0.id == id }
        for p in projects.indices { projects[p].entries.removeAll { $0.id == id } }
        save()
    }

    func clearEntries() {
        entries.removeAll()
        save()
    }

    func summary() -> String { Self.summary(of: entries) }

    func summary(of project: Project) -> String {
        project.name + "\n\n" + Self.summary(of: project.entries)
    }

    private static func summary(of entries: [Entry]) -> String {
        let width = max(entries.map(\.title.count).max() ?? 0, 5)
        var lines = entries.map { $0.title.padding(toLength: width, withPad: " ", startingAt: 0) + "   " + Format.short($0.duration) }
        lines.append("")
        lines.append("Total".padding(toLength: width, withPad: " ", startingAt: 0) + "   " + Format.short(entries.total) + "  (" + Format.hours(entries.total) + ")")
        return lines.joined(separator: "\n")
    }

    private static func title(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(Entry.maxTitleLength))
    }

    // MARK: Projects

    /// Stops the clock and waits for the session to be filed into a project.
    func finish() {
        guard !isPending else { return }
        let elapsed = elapsed()
        guard elapsed >= 1 || !entries.isEmpty else { return }
        resumeOnCancel = isRunning
        accumulated = elapsed
        startedAt = nil
        pendingFinish = elapsed
        save()
    }

    /// Moves the session's entries (plus any unlogged time, titled `lastTitle`) into a project
    /// and leaves the timer stopped at zero.
    @discardableResult
    func file(into id: Project.ID, lastTitle: String) -> Project.ID? {
        guard let i = projects.firstIndex(where: { $0.id == id }) else { return nil }
        return fileSession(at: i, lastTitle: lastTitle)
    }

    /// Like `file(into:)`, creating the project first unless one with that name already exists.
    @discardableResult
    func fileIntoNewProject(named name: String, lastTitle: String) -> Project.ID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, pendingFinish != nil else { return nil }
        if let i = projects.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return fileSession(at: i, lastTitle: lastTitle)
        }
        projects.append(Project(name: trimmed))
        return fileSession(at: projects.count - 1, lastTitle: lastTitle)
    }

    private func fileSession(at i: Int, lastTitle: String) -> Project.ID? {
        guard let unlogged = pendingFinish else { return nil }
        var filed = entries
        if unlogged >= 1 {
            filed.append(Entry(title: Self.title(lastTitle), duration: unlogged, endedAt: .now))
        }
        projects[i].entries += filed
        entries = []
        pendingFinish = nil
        accumulated = 0
        startedAt = nil
        save()
        return projects[i].id
    }

    /// Backs out of filing and puts the clock back the way it was.
    func cancelFinish() {
        guard pendingFinish != nil else { return }
        pendingFinish = nil
        if resumeOnCancel { startedAt = .now }
        save()
    }

    func renameProject(_ id: Project.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = trimmed
        save()
    }

    func deleteProject(_ id: Project.ID) {
        projects.removeAll { $0.id == id }
        save()
    }

    @discardableResult
    func addProject(named name: String) -> Project.ID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = projects.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing.id
        }
        let project = Project(name: trimmed)
        projects.append(project)
        save()
        return project.id
    }

    /// Adds or replaces an entry in a project, moving it out of wherever it was before.
    func upsert(_ entry: Entry, in projectID: Project.ID) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        var entry = entry
        entry.title = Self.title(entry.title)
        entries.removeAll { $0.id == entry.id }
        for p in projects.indices { projects[p].entries.removeAll { $0.id == entry.id } }
        if let i = projects.firstIndex(where: { $0.id == projectID }) {
            projects[i].entries.append(entry)
        }
        save()
    }

    func move(_ ids: Set<Entry.ID>, to projectID: Project.ID) {
        guard let target = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var moved: [Entry] = []
        for p in projects.indices where p != target {
            moved += projects[p].entries.filter { ids.contains($0.id) }
            projects[p].entries.removeAll { ids.contains($0.id) }
        }
        projects[target].entries += moved
        save()
    }

    func delete(_ ids: Set<Entry.ID>) {
        entries.removeAll { ids.contains($0.id) }
        for p in projects.indices { projects[p].entries.removeAll { ids.contains($0.id) } }
        save()
    }

    // MARK: Persistence

    private struct Snapshot: Codable {
        var entries: [Entry]
        var accumulated: TimeInterval
        var startedAt: Date?
        var projects: [Project]?
        var settings: BillingSettings?

        private enum CodingKeys: String, CodingKey {
            case entries = "laps", accumulated, startedAt, projects, settings
        }
    }

    @ObservationIgnored private let url: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Billy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state.json")
        // Carry data over from when the app was called Billing Timer.
        let old = support.appendingPathComponent("BillingTimer/state.json")
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.copyItem(at: old, to: url)
        }
        return url
    }()

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        entries = s.entries
        accumulated = s.accumulated
        startedAt = s.startedAt
        projects = s.projects ?? []
        settings = s.settings ?? BillingSettings()
    }

    private func save() {
        let s = Snapshot(entries: entries, accumulated: accumulated, startedAt: startedAt, projects: projects, settings: settings)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum Format {
    /// 00:42:13
    static func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// 42:13 or 1:02:13
    static func short(_ t: TimeInterval) -> String {
        let s = Int(t)
        return s < 3600
            ? String(format: "%d:%02d", s / 60, s % 60)
            : String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }

    /// Today, Yesterday, or Mon 13 Oct
    static func day(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// 12,500 kr
    static func money(_ value: Double, _ currency: String) -> String {
        let number = value.formatted(.number.precision(.fractionLength(isWholeUnits(currency) ? 0 : 2)))
        return currency.isEmpty ? number : number + " " + currency
    }

    /// Currencies billed without decimals.
    static func isWholeUnits(_ currency: String) -> Bool {
        ["kr", "isk", "kr.", "¥", "jpy"].contains(currency.lowercased())
    }

    /// 1.25 h
    static func hours(_ t: TimeInterval) -> String {
        String(format: "%.2f h", t / 3600)
    }
}
