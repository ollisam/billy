import AppKit
import SwiftUI

@main
enum BillyApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { controller = NotchController() }
    }
}

/// UI state shared between the panel and the SwiftUI views.
@Observable
@MainActor
final class NotchUI {
    var expanded = false
    var notch = CGSize(width: 190, height: 32)
    /// The entry or project being renamed.
    var editingID: UUID?

    @ObservationIgnored var contentSize: CGSize = .zero
    @ObservationIgnored var makeKey: () -> Void = {}
    @ObservationIgnored var releaseKey: () -> Void = {}
    @ObservationIgnored var openProjects: () -> Void = {}
    @ObservationIgnored var openSettings: () -> Void = {}
}

final class NotchPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchController {
    private static let canvas = CGSize(width: 640, height: 560)
    private static let expand = Animation.spring(response: 0.42, dampingFraction: 0.82)
    private static let collapse = Animation.spring(response: 0.3, dampingFraction: 0.9)

    private let store = TimerStore()
    private let ui = NotchUI()
    private let panel = NotchPanel(size: canvas)
    private lazy var projectsWindow = ProjectsWindowController(store: store)
    private var monitors: [Any] = []
    private var collapseWork: DispatchWorkItem?
    private var previousApp: NSRunningApplication?

    init() {
        let host = FirstMouseHostingView(rootView: NotchView(store: store, ui: ui))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvas)
        panel.contentView = host

        ui.makeKey = { [weak self] in
            guard let self else { return }
            if !self.panel.isKeyWindow {
                self.previousApp = NSWorkspace.shared.frontmostApplication
            }
            self.panel.makeKey()
        }
        ui.releaseKey = { [weak self] in self?.releaseKey() }
        ui.openProjects = { [weak self] in self?.projectsWindow.show() }
        ui.openSettings = { [weak self] in self?.projectsWindow.show(settings: true) }
        projectsWindow.installMainMenu()

        position()
        panel.orderFrontRegardless()

        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHover() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in handler(e); return e }) {
            monitors.append(m)
        }

        // A click anywhere else, in another app or one of ours, dismisses an open prompt.
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let clickHandler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfClickedAway() }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: clickHandler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { e in clickHandler(e); return e }) {
            monitors.append(m)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    /// Pins the canvas to the top centre of the screen with the notch (or the main screen).
    private func position() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let f = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            ui.notch = CGSize(width: f.width - left.width - right.width, height: screen.safeAreaInsets.top)
        } else {
            ui.notch = CGSize(width: 180, height: max(f.maxY - screen.visibleFrame.maxY, 24))
        }
        let size = Self.canvas
        panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private var hotRect: NSRect {
        let s = ui.contentSize, f = panel.frame
        return NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height, width: s.width, height: s.height)
    }

    private var isBusy: Bool { store.isPending || ui.editingID != nil }

    private func updateHover() {
        let inside = hotRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !ui.expanded { withAnimation(Self.expand) { ui.expanded = true } }
        } else if ui.expanded, !isBusy, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.collapseWork = nil
                guard !self.isBusy else { return }
                withAnimation(Self.collapse) { self.ui.expanded = false }
                self.releaseKey()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    /// Clicking outside the notch while it waits for a title is the same as pressing Esc:
    /// the prompt goes away and the time goes back on the clock.
    private func dismissIfClickedAway() {
        guard ui.expanded, isBusy,
              !hotRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) else { return }
        store.cancelEntry()
        store.cancelFinish()
        ui.editingID = nil
        // The click already brought another app forward; don't pull focus back to the old one.
        previousApp = nil
        collapseWork?.cancel()
        collapseWork = nil
        withAnimation(Self.collapse) { ui.expanded = false }
        panel.ignoresMouseEvents = true
    }

    /// Hands keyboard focus back to whatever app was in front.
    private func releaseKey() {
        if panel.isKeyWindow, let app = previousApp, app != .current {
            app.activate()
        }
        previousApp = nil
        DispatchQueue.main.async { [weak self] in self?.updateHover() }
    }
}
