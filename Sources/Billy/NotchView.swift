import AppKit
import ServiceManagement
import SwiftUI

struct NotchView: View {
    let store: TimerStore
    let ui: NotchUI

    var body: some View {
        let flare: CGFloat = ui.expanded ? 14 : 6
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if ui.expanded {
                    ExpandedView(store: store, ui: ui)
                        .transition(.blurReplace.combined(with: .scale(0.92, anchor: .top)))
                } else {
                    CollapsedView(store: store, ui: ui)
                        .transition(.blurReplace)
                }
            }
            .padding(.horizontal, flare)
            .background(.black)
            .clipShape(NotchShape(topRadius: flare, bottomRadius: ui.expanded ? 32 : 12))
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { ui.contentSize = $0 }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Collapsed

private struct CollapsedView: View {
    let store: TimerStore
    let ui: NotchUI

    var body: some View {
        let active = store.isRunning || store.accumulated > 0
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 0) {
                if active {
                    StatusDot(running: store.isRunning)
                        .frame(width: 64)
                }
                Color.clear.frame(width: ui.notch.width)
                if active {
                    Text(Format.short(store.elapsed(at: ctx.date)))
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 64)
                }
            }
            .frame(height: ui.notch.height)
        }
    }
}

private struct StatusDot: View {
    let running: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(running ? Color.green : Color.orange)
            .frame(width: 6, height: 6)
            .opacity(running && pulse ? 0.35 : 1)
            .animation(running ? .easeInOut(duration: 1).repeatForever() : .default, value: pulse)
            .onAppear { pulse = true }
    }
}

// MARK: - Expanded

private struct ExpandedView: View {
    let store: TimerStore
    let ui: NotchUI

    @State private var title = ""
    @State private var newProject = ""
    @State private var draft = ""
    @State private var copied = false
    @State private var splitting = false
    @State private var splitPart: TimeInterval = 0
    @State private var keyMonitor: Any?
    @FocusState private var focus: Field?

    private enum Field: Hashable { case entry, rename, newProject }
    private static let rowHeight: CGFloat = 34
    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    /// The split slider blurs in, growing down from just under the field, so it never slides over it.
    private static var sliderTransition: some Transition {
        BlurReplaceTransition(configuration: .downUp)
            .combined(with: ScaleTransition(0.94, anchor: .top))
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            timerPage
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(width: 420)
        .animation(Self.spring, value: store.pendingEntry)
        .animation(Self.spring, value: store.pendingFinish)
        .animation(Self.spring, value: store.entries)
        .animation(Self.spring, value: splitting)
        .onAppear(perform: installKeyMonitor)
        .onDisappear {
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
        .animation(Self.spring, value: store.projects)
    }

    private var header: some View {
        HStack {
            if !store.isPending {
                Button { ui.openProjects() } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 28, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Projects")
            }
            Spacer()
            Menu {
                Button("Copy Summary", action: { copy(store.summary()) }).disabled(store.entries.isEmpty)
                Button("Reset Timer", action: store.resetTimer)
                    .disabled(store.isPending || store.elapsed() == 0)
                Button("Clear Log", role: .destructive, action: store.clearEntries)
                    .disabled(store.entries.isEmpty)
                Divider()
                Button("Projects…") { ui.openProjects() }
                Button("Settings…") { ui.openSettings() }
                LaunchAtLoginToggle()
                Button("Quit Billy") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 28, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: ui.notch.height)
    }

    // MARK: Timer page

    @ViewBuilder
    private var timerPage: some View {
        controls
        if let pending = store.pendingEntry {
            naming(pending)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        if let unlogged = store.pendingFinish {
            filing(unlogged)
                .transition(.opacity.combined(with: .move(edge: .top)))
        } else if !store.entries.isEmpty {
            entryList(Array(store.entries.reversed()))
            footer(total: store.total) { copy(store.summary()) }
        }
    }

    private var controls: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = store.elapsed(at: ctx.date)
            HStack(spacing: 8) {
                RoundButton(title: "Log", tint: .white) {
                    title = ""
                    store.log()
                }
                .disabled(store.isPending || elapsed < 1)

                Spacer()
                Text(Format.clock(elapsed))
                    .font(.system(size: 38, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize()
                Spacer()

                RoundButton(title: store.isRunning ? "Pause" : "Start",
                            tint: store.isRunning ? .orange : .green,
                            action: store.toggle)
                .disabled(store.isPending)

                RoundButton(title: "Finish", tint: .red) {
                    title = ""
                    newProject = ""
                    store.finish()
                }
                .disabled(store.isPending || (elapsed < 1 && store.entries.isEmpty))
                .help("Stop and file this session into a project")
            }
        }
    }

    private func naming(_ duration: TimeInterval) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                TextField("What were you doing?", text: $title)
                    .limit($title, to: Entry.maxTitleLength)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focus, equals: .entry)
                    .onSubmit {
                        if splitting { return confirmSplit() }
                        store.commitEntry(title: title)
                        title = ""
                        ui.releaseKey()
                    }
                    .onExitCommand {
                        if splitting { return splitting = false }
                        store.cancelEntry()
                        ui.releaseKey()
                    }
                Text(Format.short(duration))
                    .font(.system(size: 13, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.45))
                    .contentTransition(.numericText())
                keyHint(remaining: duration)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(.white.opacity(0.09), in: Capsule())

            if splitting {
                SplitSlider(value: $splitPart, total: duration)
                    .transition(Self.sliderTransition)
            }
        }
        .onAppear { takeFocus(.entry) }
    }

    /// Keycaps for the two shortcuts: ⌘↩ opens (or closes) the slider, ↩ logs. ⇧↩ works too.
    private func keyHint(remaining: TimeInterval) -> some View {
        HStack(spacing: 4) {
            if remaining >= 2 {
                Keycap(keys: "⌘↩", lit: splitting)
                    .help(splitting ? "Close the slider" : "Log only part of this time")
            }
            Keycap(keys: "↩", lit: splitting)
                .help(splitting ? "Log this part and keep naming the rest" : "Log")
        }
    }

    /// Picks the project the finished session goes into.
    private func filing(_ unlogged: TimeInterval) -> some View {
        let hasUnlogged = unlogged >= 1
        let count = store.entries.count + (hasUnlogged ? 1 : 0)
        let total = store.total + (hasUnlogged ? unlogged : 0)
        let projects = store.projectsByRecent

        return VStack(spacing: 10) {
            if hasUnlogged {
                HStack(spacing: 10) {
                    TextField("What were you doing?", text: $title)
                        .limit($title, to: Entry.maxTitleLength)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($focus, equals: .entry)
                        .onSubmit {
                            if splitting { return confirmSplit() }
                            focus = .newProject
                        }
                        .onExitCommand {
                            if splitting { return splitting = false }
                            cancelFiling()
                        }
                    Text(Format.short(unlogged))
                        .font(.system(size: 13, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.45))
                        .contentTransition(.numericText())
                    keyHint(remaining: unlogged)
                }
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(.white.opacity(0.09), in: Capsule())

                if splitting {
                    SplitSlider(value: $splitPart, total: unlogged)
                        .transition(Self.sliderTransition)
                }
            }

            HStack {
                Text("File \(count) \(count == 1 ? "log" : "logs") · \(Format.short(total)) into…")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("Cancel", action: cancelFiling)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .font(.system(size: 12, weight: .medium))

            VStack(spacing: 0) {
                if !projects.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(projects) { project in
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.white.opacity(0.4))
                                    Text(project.name)
                                        .lineLimit(1)
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer(minLength: 0)
                                    Text(Format.short(project.total))
                                        .font(.system(size: 13, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 10)
                                .frame(height: Self.rowHeight)
                                .modifier(HoverHighlight())
                                .onTapGesture {
                                    finishFiling(store.file(into: project.id, lastTitle: title))
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .frame(height: min(CGFloat(projects.count), 5) * Self.rowHeight)
                }
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("New project", text: $newProject)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .newProject)
                        .onSubmit {
                            finishFiling(store.fileIntoNewProject(named: newProject, lastTitle: title))
                        }
                        .onExitCommand(perform: cancelFiling)
                    if !newProject.isEmpty {
                        Image(systemName: "return")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: Self.rowHeight)
            }
            .font(.system(size: 13))
            .padding(4)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
        .onAppear { takeFocus(hasUnlogged ? .entry : .newProject) }
    }

    // MARK: Shared pieces

    private func entryList(_ entries: [Entry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: min(CGFloat(entries.count), 6) * Self.rowHeight)
        .overlay(alignment: .top) { hairline }
    }

    private func row(_ entry: Entry) -> some View {
        HStack(spacing: 12) {
            if ui.editingID == entry.id {
                TextField("Title", text: $draft)
                    .limit($draft, to: Entry.maxTitleLength)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .rename)
                    .onSubmit { store.rename(entry.id, to: draft); endEditing() }
                    .onExitCommand { endEditing() }
            } else {
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(0.9))
                    .help(entry.endedAt.formatted(date: .abbreviated, time: .shortened))
            }
            Spacer(minLength: 0)
            Text(Format.short(entry.duration))
                .font(.system(size: 13, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 13))
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) { hairline }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginEditing(entry.id, name: entry.title) }
        .contextMenu {
            Button("Rename") { beginEditing(entry.id, name: entry.title) }
            Button("Copy") { setPasteboard("\(entry.title)   \(Format.short(entry.duration))") }
            Divider()
            Button("Delete", role: .destructive) { store.delete(entry.id) }
        }
    }

    private func footer(total: TimeInterval, copy: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text("Total")
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(Format.short(total))
                .foregroundStyle(.white)
            if store.settings.hasRate {
                Text(Format.money(store.settings.bill(total).net, store.settings.currency))
                    .foregroundStyle(.white.opacity(0.4))
                    .help("Without VSK · " + Format.money(store.settings.bill(total).gross, store.settings.currency) + " with VSK")
            } else {
                Text(Format.hours(total))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if let copy {
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(copied ? 0.9 : 0.45))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .help("Copy summary")
            }
        }
        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
    }

    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
    }

    // MARK: Actions

    private func takeFocus(_ field: Field) {
        ui.makeKey()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = field }
    }

    private func beginEditing(_ id: UUID, name: String) {
        draft = name
        ui.editingID = id
        takeFocus(.rename)
    }

    private func endEditing() {
        guard ui.editingID != nil else { return }
        ui.editingID = nil
        ui.releaseKey()
    }

    // MARK: Splitting

    /// ⌘↩ (or ⇧↩) in the title field opens the slider; pressing it again closes it. ↩ logs the part.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isReturn = event.keyCode == 36 || event.keyCode == 76
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard isReturn, modifiers == .command || modifiers == .shift,
                  focus == .entry, let remaining = store.pendingEntry ?? store.pendingFinish else { return event }
            if splitting {
                // ⌘↩ or ⇧↩ again backs out of splitting, without logging anything.
                splitting = false
            } else if remaining >= 2 {
                splitPart = SplitSlider.initialValue(for: remaining)
                splitting = true
            }
            return nil
        }
    }

    private func confirmSplit() {
        if store.pendingEntry != nil {
            store.splitPending(title: title, duration: splitPart.rounded())
        } else if store.pendingFinish != nil {
            store.splitUnlogged(title: title, duration: splitPart.rounded())
        }
        title = ""
        splitting = false
        focus = .entry
    }

    private func cancelFiling() {
        splitting = false
        store.cancelFinish()
        title = ""
        newProject = ""
        ui.releaseKey()
    }

    private func finishFiling(_ id: Project.ID?) {
        guard id != nil else { return }
        title = ""
        newProject = ""
        ui.releaseKey()
    }

    private func copy(_ text: String) {
        setPasteboard(text)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation { copied = false } }
    }

    private func setPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

// MARK: - Pieces

/// A small key badge, like the ⌘K in a search field.
private struct Keycap: View {
    let keys: String
    var lit = false

    var body: some View {
        Text(keys)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(lit ? 0.85 : 0.45))
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 20)
            .background(.white.opacity(lit ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: lit)
    }
}

/// A ruler you drag along to choose how much of the remaining time one part took.
private struct SplitSlider: View {
    @Binding var value: TimeInterval
    let total: TimeInterval

    @State private var lastTick = 0
    @State private var dragging = false

    /// Minor ticks between the ends; every `ticks / 4`th is a quarter mark.
    private static let ticks = 64

    /// At least a second for this part, and a second left over for the rest.
    private var range: ClosedRange<TimeInterval> { 1...max(1, total - 1) }

    static func initialValue(for total: TimeInterval) -> TimeInterval {
        max(1, (total / 2).rounded())
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This part")
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(Format.short(value))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("·  " + Format.short(total - value) + " left")
                    .foregroundStyle(.white.opacity(0.35))
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))

            GeometryReader { geo in
                let width = geo.size.width
                let x = width * CGFloat(value / total)
                ZStack(alignment: .leading) {
                    ruler(selectedUpTo: x)
                    // The red needle.
                    Capsule()
                        .fill(Color.red)
                        .frame(width: 2.5, height: dragging ? 34 : 30)
                        .shadow(color: .red.opacity(0.6), radius: dragging ? 6 : 3)
                        .offset(x: x - 1.25)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { dragging = true } }
                        set(fraction: g.location.x / width)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { dragging = false }
                    })
            }
            .frame(height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        .onAppear {
            value = min(max(value, range.lowerBound), range.upperBound)
            lastTick = Int(value / total * 4)
        }
    }

    /// Dense ticks, a taller line at every quarter. The small ticks stretch while you drag.
    private func ruler(selectedUpTo x: CGFloat) -> some View {
        GeometryReader { geo in
            let gap = geo.size.width / CGFloat(Self.ticks)
            ZStack(alignment: .leading) {
                ForEach(0...Self.ticks, id: \.self) { i in
                    let quarter = i % (Self.ticks / 4) == 0
                    let tickX = CGFloat(i) * gap
                    Capsule()
                        .fill(.white.opacity(tickX <= x ? (quarter ? 0.85 : 0.55) : (quarter ? 0.45 : 0.2)))
                        .frame(width: quarter ? 1.5 : 1,
                               height: quarter ? 22 : (dragging ? 15 : 8))
                        .offset(x: tickX - (quarter ? 0.75 : 0.5))
                        .animation(.spring(response: 0.3, dampingFraction: 0.65)
                            .delay(quarter ? 0 : Double(i) * 0.002), value: dragging)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Follows the pointer smoothly, with no snapping.
    private func set(fraction: CGFloat) {
        let raw = TimeInterval(min(max(fraction, 0), 1)) * total
        value = min(max(raw, range.lowerBound), range.upperBound)
        // A light tick on a Force Touch trackpad as the needle crosses a quarter line.
        let quarter = Int(value / total * 4)
        if quarter != lastTick {
            lastTick = quarter
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }
}

private struct RoundButton: View {
    let title: String
    let tint: Color
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 54, height: 54)
                .background(tint.opacity(tint == .white ? 0.12 : 0.2), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .opacity(isEnabled ? 1 : 0.35)
    }
}

private struct HoverHighlight: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(hovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at Login", isOn: Binding(
            get: { enabled },
            set: { on in
                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                enabled = SMAppService.mainApp.status == .enabled
            }
        ))
    }
}

/// A notch silhouette: flared top corners that melt into the menu bar, round bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, r.height - t, (r.width - 2 * t) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + t, y: r.minY + t), control: CGPoint(x: r.minX + t, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + t, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + t + b, y: r.maxY), control: CGPoint(x: r.minX + t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - t, y: r.maxY - b), control: CGPoint(x: r.maxX - t, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - t, y: r.minY + t))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - t, y: r.minY))
        p.closeSubpath()
        return p
    }
}
