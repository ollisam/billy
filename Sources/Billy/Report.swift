import AppKit
import SwiftUI

enum Period: String, CaseIterable, Identifiable {
    case all = "All Time"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case lastMonth = "Last Month"

    var id: Self { self }

    func contains(_ date: Date, now: Date = .now) -> Bool {
        let cal = Calendar.current
        switch self {
        case .all: return true
        case .thisWeek: return cal.isDate(date, equalTo: now, toGranularity: .weekOfYear)
        case .thisMonth: return cal.isDate(date, equalTo: now, toGranularity: .month)
        case .lastMonth:
            guard let last = cal.date(byAdding: .month, value: -1, to: now) else { return false }
            return cal.isDate(date, equalTo: last, toGranularity: .month)
        }
    }

    /// "October 2026", "All time", …
    func title(now: Date = .now) -> String {
        let cal = Calendar.current
        switch self {
        case .all: return "All time"
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return "Week of " + start.formatted(.dateTime.day().month(.wide).year())
        case .thisMonth: return now.formatted(.dateTime.month(.wide).year())
        case .lastMonth:
            let last = cal.date(byAdding: .month, value: -1, to: now) ?? now
            return last.formatted(.dateTime.month(.wide).year())
        }
    }
}

/// A project's logs for one period, with billing worked out.
struct Report {
    let project: Project
    let period: Period
    let settings: BillingSettings
    /// Oldest first.
    let entries: [Entry]

    init(project: Project, period: Period, settings: BillingSettings) {
        self.project = project
        self.period = period
        self.settings = settings
        entries = project.entries.filter { period.contains($0.endedAt) }.sorted { $0.endedAt < $1.endedAt }
    }

    var total: TimeInterval { entries.total }
    var billing: Billing { settings.bill(total) }

    var days: [(day: Date, entries: [Entry])] {
        Dictionary(grouping: entries) { Calendar.current.startOfDay(for: $0.endedAt) }
            .map { (day: $0.key, entries: $0.value) }
            .sorted { $0.day < $1.day }
    }

    /// "3 Oct – 15 Oct 2026"
    var dateRange: String {
        guard let first = entries.first?.endedAt, let last = entries.last?.endedAt else { return "No logs" }
        let end = last.formatted(.dateTime.day().month(.abbreviated).year())
        if Calendar.current.isDate(first, inSameDayAs: last) { return end }
        return first.formatted(.dateTime.day().month(.abbreviated)) + " – " + end
    }

    var fileName: String { "\(project.name) – \(period.title())" }

    func money(_ value: Double) -> String { Format.money(value, settings.currency) }

    // MARK: Text

    func text() -> String {
        var lines: [String] = []
        lines.append(project.name + " — " + period.title())
        lines.append("")
        let width = max(entries.map(\.title.count).max() ?? 0, 20)
        for (day, dayEntries) in days {
            lines.append(Format.day(day) + "   " + Format.short(dayEntries.total))
            for e in dayEntries {
                lines.append("  " + e.title.padding(toLength: width, withPad: " ", startingAt: 0) + "   " + Format.short(e.duration))
            }
        }
        lines.append("")
        lines.append("Total time        " + Format.short(total) + "  (" + Format.hours(total) + ")")
        if settings.hasRate {
            let b = billing
            lines.append("Rate              " + money(settings.hourlyRate) + " / h")
            lines.append("Amount ex. VSK    " + money(b.net))
            lines.append(("VSK " + Format.percent(settings.vatPercent)).padding(toLength: 18, withPad: " ", startingAt: 0) + money(b.vat))
            lines.append("Total incl. VSK   " + money(b.gross))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: CSV

    func csv() -> String {
        func field(_ s: String) -> String {
            s.contains(where: { ",\"\n".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func number(_ v: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", v) }

        var rows = [["Date", "Description", "Duration", "Hours", "Amount ex. VSK", "VSK", "Total incl. VSK"]]
        for e in entries {
            let b = settings.bill(e.duration)
            rows.append([e.endedAt.formatted(.iso8601.year().month().day()), e.title, Format.short(e.duration),
                         number(b.hours), number(b.net), number(b.vat), number(b.gross)])
        }
        let b = billing
        rows.append(["", "Total", Format.short(total), number(b.hours), number(b.net), number(b.vat), number(b.gross)])
        return rows.map { $0.map(field).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    // MARK: PDF

    fileprivate enum Line: Identifiable {
        case day(Date, TimeInterval)
        case entry(Entry)

        var id: String {
            switch self {
            case .day(let d, _): return "day-\(d.timeIntervalSince1970)"
            case .entry(let e): return e.id.uuidString
            }
        }
    }

    fileprivate static let pageSize = CGSize(width: 595, height: 842) // A4

    @MainActor
    func writePDF(to url: URL) throws {
        let lines = days.flatMap { group in
            [Line.day(group.day, group.entries.total)] + group.entries.map(Line.entry)
        }

        // Fixed-height rows make pagination a matter of counting.
        let firstCapacity = 30, capacity = 42, totalsLines = 7
        var pages: [[Line]] = []
        var rest = lines[...]
        repeat {
            let take = pages.isEmpty ? firstCapacity : capacity
            pages.append(Array(rest.prefix(take)))
            rest = rest.dropFirst(take)
        } while !rest.isEmpty
        let lastCapacity = pages.count == 1 ? firstCapacity : capacity
        if pages[pages.count - 1].count + totalsLines > lastCapacity { pages.append([]) }

        var box = CGRect(origin: .zero, size: Self.pageSize)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (i, page) in pages.enumerated() {
            let view = ReportPage(report: self, lines: page, number: i + 1, count: pages.count)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(Self.pageSize)
            renderer.render { _, draw in
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
            }
        }
        ctx.closePDF()
    }
}

private struct ReportPage: View {
    let report: Report
    let lines: [Report.Line]
    let number: Int
    let count: Int

    private static let rowHeight: CGFloat = 16
    private var showMoney: Bool { report.settings.hasRate }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if number == 1 { header }
            if !lines.isEmpty { columns }
            ForEach(lines) { line in
                switch line {
                case .day(let day, let total):
                    row(Format.day(day), time: Format.short(total), amount: amount(total), bold: true)
                        .padding(.top, 4)
                        .frame(height: Self.rowHeight + 4, alignment: .bottom)
                case .entry(let e):
                    row(e.title, time: Format.short(e.duration), amount: amount(e.duration), bold: false)
                        .padding(.leading, 10)
                }
            }
            if number == count { totals.padding(.top, 18) }
            Spacer(minLength: 0)
            HStack {
                Text("Generated " + Date.now.formatted(date: .abbreviated, time: .shortened))
                Spacer()
                Text("Page \(number) of \(count)")
            }
            .font(.system(size: 8))
            .foregroundStyle(.gray)
        }
        .padding(48)
        .frame(width: Report.pageSize.width, height: Report.pageSize.height, alignment: .topLeading)
        .background(.white)
        .foregroundStyle(.black)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(report.project.name)
                .font(.system(size: 22, weight: .bold))
            Text(report.period.title() + "  ·  " + report.dateRange)
                .font(.system(size: 10))
                .foregroundStyle(.gray)
        }
        .padding(.bottom, 22)
    }

    private var columns: some View {
        VStack(spacing: 0) {
            row("Description", time: "Time", amount: showMoney ? "Amount" : nil, bold: true)
                .foregroundStyle(.gray)
            Rectangle().fill(.black.opacity(0.15)).frame(height: 0.5)
        }
    }

    private func amount(_ d: TimeInterval) -> String? {
        showMoney ? report.money(report.settings.bill(d).net) : nil
    }

    private func row(_ title: String, time: String, amount: String?, bold: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title).lineLimit(1)
            Spacer(minLength: 0)
            Text(time).frame(width: 60, alignment: .trailing)
            if let amount { Text(amount).frame(width: 90, alignment: .trailing) }
        }
        .font(.system(size: 9.5, weight: bold ? .semibold : .regular).monospacedDigit())
        .frame(height: Self.rowHeight)
    }

    private var totals: some View {
        let b = report.billing
        return VStack(spacing: 5) {
            Rectangle().fill(.black.opacity(0.15)).frame(height: 0.5)
            totalRow("Total time", Format.short(report.total) + "  (" + Format.hours(report.total) + ")")
            if showMoney {
                totalRow("Rate", report.money(report.settings.hourlyRate) + " / h")
                totalRow("Amount ex. VSK", report.money(b.net))
                totalRow("VSK " + Format.percent(report.settings.vatPercent), report.money(b.vat))
                totalRow("Total incl. VSK", report.money(b.gross), strong: true)
            }
        }
        .padding(.leading, 260)
    }

    private func totalRow(_ label: String, _ value: String, strong: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(strong ? .black : .gray)
            Spacer()
            Text(value)
        }
        .font(.system(size: strong ? 12 : 10, weight: strong ? .bold : .regular).monospacedDigit())
    }
}

extension Format {
    /// 24%
    static func percent(_ p: Double) -> String {
        p.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }
}
