import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Navigation state for the projects window, kept across opens.
@Observable
@MainActor
final class ProjectsNav {
    var selection: Project.ID?
    var period: Period = .thisMonth
    var showSettings = false
}

@MainActor
final class ProjectsWindowController: NSObject, NSWindowDelegate {
    private let store: TimerStore
    private let nav = ProjectsNav()
    private var window: NSWindow?

    init(store: TimerStore) {
        self.store = store
    }

    @objc func showProjects() { show() }
    @objc func showSettings() { show(settings: true) }

    func show(project: Project.ID? = nil, settings: Bool = false) {
        let window = self.window ?? makeWindow()
        if let project { nav.selection = project }
        if nav.selection == nil { nav.selection = store.projectsByRecent.first?.id }
        if settings { nav.showSettings = true }

        // A regular app while the window is open, so it gets a Dock icon, ⌘-Tab and a menu bar.
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Projects"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        // Dark everywhere, including sheets, alerts and save panels.
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentMinSize = NSSize(width: 760, height: 460)
        window.contentView = NSHostingView(rootView: ProjectsView(store: store, nav: nav))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("ProjectsWindow")
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Without a main menu, ⌘C/⌘V/⌘Z don't reach text fields.
    func installMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "Projects", action: #selector(showProjects), keyEquivalent: "p").target = self
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Billy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")

        for menu in [app, edit, windowMenu] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }
}

// MARK: - Window content

struct ProjectsView: View {
    let store: TimerStore
    @Bindable var nav: ProjectsNav

    @State private var nameRequest: NameRequest?
    @State private var name = ""
    @State private var deleting: Project?

    private struct NameRequest: Identifiable {
        var id: Project.ID?
        var title: String
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
            Hairline(vertical: true)
            Group {
                if let id = nav.selection, let project = store.project(id) {
                    ProjectDetail(store: store, nav: nav, project: project)
                        .id(id)
                } else {
                    Text(store.projects.isEmpty ? "Press Finish in the notch to file your logs into a project." : "Select a project.")
                        .font(Ink.body)
                        .foregroundStyle(Ink.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .sheet(isPresented: $nav.showSettings) {
            SettingsView(store: store)
        }
        .alert(nameRequest?.title ?? "", isPresented: Binding(get: { nameRequest != nil },
                                                              set: { if !$0 { nameRequest = nil } })) {
            TextField("Name", text: $name)
            Button("Save", action: commitName)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.name ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Project", role: .destructive) {
                if let deleting { store.deleteProject(deleting.id) }
            }
        } message: {
            Text("Its \(deleting?.entries.count ?? 0) logs will be deleted too. This can't be undone.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Projects")
                .font(Ink.caption)
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 52)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.projectsByRecent) { project in
                        sidebarRow(project)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)

            HStack {
                Button { askName(for: nil) } label: { Image(systemName: "plus") }
                    .help("New Project")
                Spacer()
                Button { nav.showSettings = true } label: { Image(systemName: "gearshape") }
                    .help("Settings")
            }
            .buttonStyle(IconStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.white.opacity(0.025))
    }

    private func sidebarRow(_ project: Project) -> some View {
        let selected = nav.selection == project.id
        return HStack {
            Text(project.name)
                .lineLimit(1)
                .foregroundStyle(selected ? Ink.primary : Ink.primary.opacity(0.75))
            Spacer(minLength: 8)
            Text(Format.hours(project.total))
                .font(Ink.number(12))
                .foregroundStyle(Ink.tertiary)
        }
        .font(Ink.body)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(selected ? Ink.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { nav.selection = project.id }
        .contextMenu {
            Button("Rename…") { askName(for: project) }
            Divider()
            Button("Delete Project…", role: .destructive) { deleting = project }
        }
    }

    private func askName(for project: Project?) {
        name = project?.name ?? ""
        nameRequest = NameRequest(id: project?.id, title: project == nil ? "New Project" : "Rename Project")
    }

    private func commitName() {
        if let id = nameRequest?.id {
            store.renameProject(id, to: name)
        } else if let id = store.addProject(named: name) {
            nav.selection = id
        }
    }
}

// MARK: - Project detail

private struct ProjectDetail: View {
    let store: TimerStore
    @Bindable var nav: ProjectsNav
    let project: Project

    @State private var selection = Set<Entry.ID>()
    @State private var editing: EntryDraft?
    @State private var deleting: Set<Entry.ID> = []
    #if INVOICES
    @State private var invoicing = false
    #endif
    @FocusState private var listFocused: Bool

    private static let periods: [(Period, String)] = [
        (.thisWeek, "Week"), (.thisMonth, "Month"), (.lastMonth, "Last Month"), (.all, "All"),
    ]

    var body: some View {
        let report = Report(project: project, period: nav.period, settings: store.settings)
        VStack(alignment: .leading, spacing: 0) {
            header(report)
            stats(report)
                .padding(.top, 28)
            actions(report)
                .padding(.top, 28)
                .padding(.bottom, 14)
            Hairline()
            list(report)
        }
        .padding(.horizontal, 32)
        .sheet(item: $editing) { draft in
            EntryEditor(store: store, draft: draft)
        }
        #if INVOICES
        .sheet(isPresented: $invoicing) {
            InvoiceSheet(store: store, report: report)
        }
        #endif
        .confirmationDialog(deleting.count == 1 ? "Delete this log?" : "Delete \(deleting.count) logs?",
                            isPresented: Binding(get: { !deleting.isEmpty }, set: { if !$0 { deleting = [] } })) {
            Button("Delete", role: .destructive) {
                store.delete(deleting)
                selection.subtract(deleting)
            }
        }
    }

    private func header(_ report: Report) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(report.period.title())
                    .font(Ink.body)
                    .foregroundStyle(Ink.secondary)
            }
            Spacer()
            Segments(options: Self.periods, selection: $nav.period)
        }
        .padding(.top, 48)
    }

    @ViewBuilder
    private func stats(_ report: Report) -> some View {
        let b = report.billing
        HStack(alignment: .top, spacing: 40) {
            Stat(label: "Time", value: Format.hours(report.total))
            if store.settings.hasRate {
                Stat(label: "Without VSK", value: report.money(b.net))
                Stat(label: "With VSK", value: report.money(b.gross))
            } else {
                Button { nav.showSettings = true } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No hourly rate")
                            .font(Ink.caption)
                            .foregroundStyle(Ink.tertiary)
                        Text("Set your rate to see what this is worth →")
                            .font(Ink.body)
                            .foregroundStyle(Ink.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ report: Report) -> some View {
        HStack(spacing: 8) {
            Button { editing = EntryDraft(projectID: project.id) } label: {
                Label("Add Log", systemImage: "plus")
            }
            .buttonStyle(PillStyle())

            Spacer()

            Menu {
                Button("Copy Report") { copyReport(report) }
                Divider()
                Button("Save Report PDF…") { savePDF(report) }
                Button("Save CSV…") { saveCSV(report) }
            } label: {
                Text("Export")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(report.entries.isEmpty)
            .opacity(report.entries.isEmpty ? 0.35 : 1)

            #if INVOICES
            Button("Create Invoice") { invoicing = true }
                .buttonStyle(PillStyle(prominent: true))
                .disabled(report.entries.isEmpty)
            #endif
        }
    }

    // MARK: Log list

    private static let rowHeight: CGFloat = 36

    @ViewBuilder
    private func list(_ report: Report) -> some View {
        if report.entries.isEmpty {
            Text("Nothing logged \(nav.period == .all ? "yet" : "in " + nav.period.title()).")
                .font(Ink.body)
                .foregroundStyle(Ink.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(report.days.reversed(), id: \.day) { group in
                        HStack {
                            Text(Format.day(group.day))
                            Spacer()
                            Text(Format.short(group.entries.total))
                                .font(Ink.number(11, weight: .semibold))
                        }
                        .font(Ink.caption)
                        .foregroundStyle(Ink.tertiary)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                        .padding(.horizontal, 10)
                        ForEach(group.entries.reversed()) { entry in
                            row(entry, report: report)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.never)
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onDeleteCommand { if !selection.isEmpty { deleting = selection } }
            .onExitCommand { selection = [] }
        }
    }

    private func row(_ entry: Entry, report: Report) -> some View {
        let selected = selection.contains(entry.id)
        return HStack(spacing: 16) {
            Text(entry.endedAt.formatted(date: .omitted, time: .shortened))
                .font(Ink.number(12))
                .foregroundStyle(Ink.tertiary)
                .frame(width: 64, alignment: .leading)
            Text(entry.title)
                .lineLimit(1)
                .foregroundStyle(Ink.primary)
            Spacer(minLength: 8)
            Text(Format.short(entry.duration))
                .font(Ink.number())
                .foregroundStyle(Ink.secondary)
            if store.settings.hasRate {
                Text(report.money(store.settings.bill(entry.duration).net))
                    .font(Ink.number())
                    .foregroundStyle(Ink.secondary)
                    .frame(width: 110, alignment: .trailing)
            }
        }
        .font(Ink.body)
        .padding(.horizontal, 10)
        .frame(height: Self.rowHeight)
        .background(selected ? Ink.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = EntryDraft(entry, projectID: project.id) }
        .simultaneousGesture(TapGesture().onEnded { select(entry.id) })
        .contextMenu {
            let ids = selection.contains(entry.id) ? selection : [entry.id]
            if ids.count == 1 {
                Button("Edit…") { editing = EntryDraft(entry, projectID: project.id) }
            }
            let others = store.projectsByRecent.filter { $0.id != project.id }
            if !others.isEmpty {
                Menu("Move to") {
                    ForEach(others) { other in
                        Button(other.name) { store.move(ids, to: other.id) }
                    }
                }
            }
            Divider()
            Button(ids.count == 1 ? "Delete…" : "Delete \(ids.count) Logs…", role: .destructive) { deleting = ids }
        }
    }

    private func select(_ id: Entry.ID) {
        listFocused = true
        if NSEvent.modifierFlags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    // MARK: Export

    private func copyReport(_ report: Report) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text(), forType: .string)
    }

    private func savePDF(_ report: Report) {
        guard let url = askSaveURL(report.fileName, type: .pdf) else { return }
        do {
            try report.writePDF(to: url)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func saveCSV(_ report: Report) {
        guard let url = askSaveURL(report.fileName, type: .commaSeparatedText) else { return }
        do {
            try report.csv().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func askSaveURL(_ name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

private struct Stat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Ink.caption)
                .foregroundStyle(Ink.tertiary)
            Text(value)
                .font(Ink.number(26, weight: .medium))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Editing a log

/// The editable state of a log, kept as text so fields respond to every keystroke.
private struct EntryDraft: Identifiable {
    var id: Entry.ID
    var isNew: Bool
    var title: String
    var day: Date
    var hour: String
    var minute: String
    var durationHours: String
    var durationMinutes: String
    var seconds: Int
    var projectID: Project.ID

    init(projectID: Project.ID) {
        let now = Date.now
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        id = UUID()
        isNew = true
        title = ""
        day = now
        hour = String(format: "%02d", c.hour ?? 0)
        minute = String(format: "%02d", c.minute ?? 0)
        durationHours = ""
        durationMinutes = ""
        seconds = 0
        self.projectID = projectID
    }

    init(_ entry: Entry, projectID: Project.ID) {
        let s = Int(entry.duration)
        let c = Calendar.current.dateComponents([.hour, .minute], from: entry.endedAt)
        id = entry.id
        isNew = false
        title = entry.title
        day = entry.endedAt
        hour = String(format: "%02d", c.hour ?? 0)
        minute = String(format: "%02d", c.minute ?? 0)
        durationHours = s >= 3600 ? String(s / 3600) : ""
        durationMinutes = s % 3600 >= 60 ? String(s / 60 % 60) : ""
        seconds = s % 60
        self.projectID = projectID
    }

    var duration: TimeInterval {
        TimeInterval((Int(durationHours) ?? 0) * 3600 + (Int(durationMinutes) ?? 0) * 60 + seconds)
    }

    var endedAt: Date {
        let cal = Calendar.current
        return cal.date(bySettingHour: min(Int(hour) ?? 0, 23), minute: min(Int(minute) ?? 0, 59), second: 0,
                        of: cal.startOfDay(for: day)) ?? day
    }

    var isValid: Bool { duration >= 1 }
    var entry: Entry { Entry(id: id, title: title, duration: duration, endedAt: endedAt) }
}

private struct EntryEditor: View {
    let store: TimerStore
    @State var draft: EntryDraft
    @State private var showCalendar = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case title, hour, minute, durationHours, durationMinutes }

    var body: some View {
        SheetChrome(title: draft.isNew ? "Add Log" : "Edit Log") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    TextField("What were you doing?", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($focus, equals: .title)
                        .onSubmit(next)
                        .limit($draft.title, to: Entry.maxTitleLength)
                    // Shows up as you get close to the limit.
                    if draft.title.count >= Entry.maxTitleLength - 10 {
                        Text("\(Entry.maxTitleLength - draft.title.count)")
                            .font(Ink.number(12))
                            .foregroundStyle(draft.title.count >= Entry.maxTitleLength ? Ink.primary : Ink.tertiary)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .modifier(FieldBox(focused: focus == .title))
                .padding(.top, 10)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        label("Date")
                        dateButton
                    }
                    GridRow {
                        label("Time")
                        HStack(spacing: 4) {
                            DigitsField(placeholder: "00", text: $draft.hour, maxLength: 2, max: 23, focused: focus == .hour)
                                .focused($focus, equals: .hour)
                                .modifier(FieldBox(focused: focus == .hour))
                                .onSubmit(next)
                            Text(":").foregroundStyle(Ink.tertiary)
                            DigitsField(placeholder: "00", text: $draft.minute, maxLength: 2, max: 59, focused: focus == .minute)
                                .focused($focus, equals: .minute)
                                .modifier(FieldBox(focused: focus == .minute))
                                .onSubmit(next)
                        }
                    }
                    GridRow {
                        label("Duration")
                        HStack(spacing: 6) {
                            DigitsField(placeholder: "0", text: $draft.durationHours, maxLength: 3, focused: focus == .durationHours)
                                .focused($focus, equals: .durationHours)
                                .modifier(FieldBox(focused: focus == .durationHours))
                                .onSubmit(next)
                            Text("h").foregroundStyle(Ink.tertiary)
                            DigitsField(placeholder: "0", text: $draft.durationMinutes, maxLength: 3, focused: focus == .durationMinutes)
                                .focused($focus, equals: .durationMinutes)
                                .modifier(FieldBox(focused: focus == .durationMinutes))
                                .onSubmit(next)
                            Text("m").foregroundStyle(Ink.tertiary)
                        }
                    }
                    GridRow {
                        label("Project")
                        InlineMenu(options: store.projectsByRecent.map { ($0.id, $0.name) }, selection: $draft.projectID)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .modifier(FieldBox(focused: false))
                    }
                }
                .font(Ink.body)

                summary
            }
        } buttons: {
            Button("Cancel") { dismiss() }
                .buttonStyle(PillStyle())
                .keyboardShortcut(.cancelAction)
            Button(draft.isNew ? "Add Log" : "Save", action: save)
                .buttonStyle(PillStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
                // ⌘S saves too, from any field.
                .background {
                    Button("", action: save)
                        .keyboardShortcut("s", modifiers: .command)
                        .opacity(0)
                        .allowsHitTesting(false)
                }
        }
        .frame(width: 440)
        .onAppear {
            DispatchQueue.main.async { focus = draft.isNew ? .title : .durationHours }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Ink.secondary)
            .frame(width: 70, alignment: .leading)
    }

    private var dateButton: some View {
        Button { showCalendar.toggle() } label: {
            HStack(spacing: 8) {
                Text(draft.day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .foregroundStyle(Ink.primary)
                Image(systemName: "calendar")
                    .foregroundStyle(Ink.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .modifier(FieldBox(focused: showCalendar))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
            MonthCalendar(selection: $draft.day) { showCalendar = false }
        }
    }

    @ViewBuilder
    private var summary: some View {
        let d = draft.duration
        HStack {
            Text(d > 0 ? Format.short(d) : "No time yet")
                .font(Ink.number())
                .foregroundStyle(d > 0 ? Ink.secondary : Ink.tertiary)
            Spacer()
            if store.settings.hasRate, d > 0 {
                let b = store.settings.bill(d)
                Text(Format.money(b.net, store.settings.currency))
                    .font(Ink.number())
                    .foregroundStyle(Ink.primary)
                Text("·  " + Format.money(b.gross, store.settings.currency) + " with VSK")
                    .font(Ink.number())
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Hairline() }
        .animation(.default, value: d)
    }

    /// Return moves to the next field, and saves from the last one.
    private func next() {
        switch focus {
        case .title: focus = .durationHours
        case .durationHours: focus = .durationMinutes
        case .hour: focus = .minute
        default: if draft.isValid { save() }
        }
    }

    private func save() {
        guard draft.isValid else { return }
        store.upsert(draft.entry, in: draft.projectID)
        dismiss()
    }
}

/// A small box around an editable field; brighter while it has focus.
private struct FieldBox: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .background(focused ? Color.white.opacity(0.12) : Ink.fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(focused ? 0.25 : 0), lineWidth: 1)
            }
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

/// A short numbers-only field that ignores anything else you type.
private struct DigitsField: View {
    let placeholder: String
    @Binding var text: String
    var maxLength: Int
    var max: Int?
    /// The placeholder disappears while the field has focus, leaving just the cursor.
    var focused = false

    var body: some View {
        TextField(focused ? "" : placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Ink.number(14))
            .multilineTextAlignment(.center)
            .frame(width: CGFloat(maxLength) * 10 + 22, height: 30)
            .onChange(of: text) { _, new in
                var digits = String(new.filter(\.isNumber).prefix(maxLength))
                if let max, let n = Int(digits), n > max { digits = String(max) }
                if digits != new { text = digits }
            }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var store: TimerStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = store.settings
        SheetChrome(title: "Settings") {
            ScrollView {
                VStack(spacing: 0) {
                    Caption("Billing")
                    FieldRow("Hourly rate") {
                        InlineNumberField(placeholder: "0", value: $store.settings.hourlyRate)
                    }
                    FieldRow("Currency") {
                        InlineMenu(options: Currency.options(including: s.currency), selection: $store.settings.currency)
                    }
                    FieldRow("VSK %") {
                        InlineNumberField(placeholder: "24", value: $store.settings.vatPercent)
                    }
                    if s.hasRate {
                        let hour = s.bill(3600)
                        FieldRow("1 hour") {
                            Text(Format.money(hour.net, s.currency) + "  ·  " + Format.money(hour.gross, s.currency) + " with VSK")
                                .font(Ink.number())
                                .foregroundStyle(Ink.secondary)
                        }
                    }

                    #if INVOICES
                    InvoiceSettingsSection()
                    #endif
                }
            }
            .scrollIndicators(.never)
        } buttons: {
            Button("Done") { dismiss() }
                .buttonStyle(PillStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .frame(width: 460, height: 640)
    }
}

/// Currencies offered in Settings. "kr" is Icelandic krónur, as it always has been here.
enum Currency {
    static let common: [(String, String)] = [
        ("kr", "ISK"),
        ("EUR", "EUR"),
        ("USD", "USD"),
        ("GBP", "GBP"),
        ("DKK", "DKK"),
        ("SEK", "SEK"),
        ("NOK", "NOK"),
        ("CHF", "CHF"),
    ]

    /// The common list, plus whatever was typed in before if it isn't on it.
    static func options(including current: String) -> [(String, String)] {
        common.contains { $0.0 == current } || current.isEmpty ? common : common + [(current, current)]
    }
}
