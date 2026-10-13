import AppKit
import Combine
import SwiftUI

@main
enum Main {
    static func main() {
        let app = SpindleApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// AppKit asks the application which way its interface runs, and that answer
/// drives tab bars, scrollers and title bars that SwiftUI's environment can't reach.
final class SpindleApplication: NSApplication {
    override var userInterfaceLayoutDirection: NSUserInterfaceLayoutDirection {
        appLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MusicViewModel()
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var widget: NSPanel?
    private var widgetLayout = ""
    private let wallpaper = WallpaperManager()
    private var notches: [Notch] = []
    private var notchesOnAllDisplays = true
    private var notchWatchdog: Timer?
    private var playerWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: "Spindle")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        let card = NSHostingController(rootView: PlayerCardView(model: model).environment(\.layoutDirection, appLayoutDirection))
        // Without a size up front the popover is placed as if empty and its top lands off-screen.
        card.sizingOptions = .preferredContentSize
        popover.contentViewController = card
        popover.contentSize = card.view.fittingSize

        settings.openWindow = { [weak self] in self?.showSettings() }
        settings.openPlayer = { [weak self] in self?.showPlayer() }
        // The change is announced before it lands, so apply on the next turn of the run loop.
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.applySettings() }
            .store(in: &subscriptions)
        model.$artwork.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.applyDockIcon()
                self?.applyWallpaper()
            }
        }
        .store(in: &subscriptions)
        HotKeyCenter.shared.handler = { [weak self] in self?.perform($0) }
        applySettings()
        // `open Spindle.app --args --settings` goes straight to the settings window.
        if CommandLine.arguments.contains("--settings") { showSettings() }
        // The first launch opens on the guide, since nothing else explains the permission prompt.
        if !settings.hasSeenGuide {
            settings.hasSeenGuide = true
            settings.initialTab = .guide
            showSettings()
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.notches.isEmpty else { return }
            self.setNotch(visible: false)
            self.setNotch(visible: true)
        }
    }

    /// Opening the app again is the way back in when both the menu bar icon and the Dock icon are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPlayer()
        if !settings.showMenuBarIcon { showSettings() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaper.restore()
    }

    private func applyWallpaper() {
        wallpaper.update(enabled: settings.coverAsWallpaper, allDisplays: settings.allDisplays, artwork: model.artwork,
                         trackID: model.track.map { "\($0.source.rawValue)-\($0.id)" })
    }

    private func applySettings() {
        statusItem.isVisible = settings.showMenuBarIcon
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        applyDockIcon()
        setWidget(visible: settings.showWidget)
        widget?.level = settings.widgetLevel.windowLevel
        let shadow = settings.widgetShadow && settings.widgetBackground != .transparent && settings.widgetTheme != .record
        if widget?.hasShadow != shadow { widget?.hasShadow = shadow }
        widget?.invalidateShadow()
        applyWallpaper()
        // The pills are built per display, so a change to that choice means rebuilding them.
        if notchesOnAllDisplays != settings.allDisplays, !notches.isEmpty { setNotch(visible: false) }
        setNotch(visible: settings.showNotch)
        applyPlayerWindowStyle()
    }

    private func applyPlayerWindowStyle() {
        // The frosted background only shows through a window that isn't opaque.
        playerWindow?.isOpaque = !settings.transparentPlayer
        playerWindow?.backgroundColor = settings.transparentPlayer ? .clear : .windowBackgroundColor
    }

    private func applyDockIcon() {
        guard settings.showDockIcon, settings.artworkInDock, let artwork = model.artwork else {
            NSApp.applicationIconImage = nil
            return
        }
        // Dock icons are drawn inset with rounded corners; a bare square cover looks oversized.
        let size = NSSize(width: 256, height: 256)
        NSApp.applicationIconImage = NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 24, dy: 24)
            NSBezierPath(roundedRect: inset, xRadius: 44, yRadius: 44).addClip()
            artwork.draw(in: inset)
            return true
        }
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .playPause: model.playPause()
        case .next: model.next()
        case .previous: model.previous()
        case .togglePopover: togglePopover()
        case .toggleNotch: notches.forEach { $0.state.pinned.toggle() }
        case .toggleMenuBarIcon: settings.showMenuBarIcon.toggle()
        }
    }

    private func showPlayer() {
        popover.performClose(nil)
        if playerWindow == nil {
            let root = PlayerWindowView(model: model).environment(\.layoutDirection, appLayoutDirection)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.title = "Spindle"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            // The window starts with no size, and centering that puts its corner mid-screen.
            window.setContentSize(window.contentViewController?.view.fittingSize ?? .zero)
            window.center()
            playerWindow = window
        }
        applyPlayerWindowStyle()
        NSApp.activate(ignoringOtherApps: true)
        playerWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model).environment(\.layoutDirection, appLayoutDirection)))
            window.title = L("Spindle Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(window.contentViewController?.view.fittingSize ?? .zero)
            window.center()
            settingsWindow = window
        }
        // A menu-bar app is never frontmost by itself, so the window would open behind others.
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func makePanel<Content: View>(_ content: Content) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // The widget and the notch are pictures of physical things and keep their direction.
        panel.contentView = NSHostingView(rootView: content.environment(\.layoutDirection, .leftToRight))
        return panel
    }

    private func setWidget(visible: Bool) {
        guard visible else {
            widget?.close()
            widget = nil
            return
        }
        // The theme and size decide the window's size, so a change means resizing in place.
        let layout = settings.widgetTheme.rawValue + settings.widgetSize.rawValue
        let size = WidgetView.size(for: settings)
        if let widget {
            guard layout != widgetLayout else { return }
            widgetLayout = layout
            let top = widget.frame.maxY
            widget.setFrame(NSRect(x: widget.frame.minX, y: top - size.height, width: size.width, height: size.height),
                            display: true)
            return
        }
        widgetLayout = layout
        let panel = makePanel(WidgetView(model: model))
        panel.isMovableByWindowBackground = true
        panel.level = settings.widgetLevel.windowLevel
        // Remember where the top-left corner was dragged to; the size comes from the theme.
        panel.setContentSize(size)
        let saved = (UserDefaults.standard.string(forKey: "widgetTopLeft") ?? "").split(separator: ",").compactMap { Double($0) }
        if saved.count == 2 {
            panel.setFrameTopLeftPoint(NSPoint(x: saved[0], y: saved[1]))
        }
        // A saved spot can end up off every display (unplugged monitor, bigger theme); start over then.
        if saved.count != 2 || !NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: 40, dy: 40).intersects(panel.frame) }) {
            panel.center()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { _ in
            UserDefaults.standard.set("\(panel.frame.minX),\(panel.frame.maxY)", forKey: "widgetTopLeft")
        }
        panel.orderFrontRegardless()
        widget = panel
    }

    /// One pill and the two regions that decide when it opens and closes.
    private struct Notch {
        let panel: NSPanel
        let state: NotchState
        let screen: NSScreen
        let collapsed: NSRect
        let expanded: NSRect
    }

    /// A full-screen space takes the menu bar's window off that display. The screen's
    /// own visible frame can't be used for this: it keeps reporting the bar's height.
    private static func screensShowingMenuBar() -> [NSScreen] {
        let level = Int(CGWindowLevelForKey(.mainMenuWindow))
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let bars: [CGRect] = windows.compactMap {
            guard $0[kCGWindowLayer as String] as? Int == level,
                  $0[kCGWindowOwnerName as String] as? String == "Window Server",
                  let bounds = $0[kCGWindowBounds as String] as? NSDictionary else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }
        // Window bounds count down from the top of the primary display; screen frames count up.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSScreen.screens.filter { screen in
            let top = CGPoint(x: screen.frame.midX, y: primaryHeight - screen.frame.maxY + 2)
            return bars.contains { $0.contains(top) }
        }
    }

    private func setNotch(visible: Bool) {
        guard visible else {
            notchWatchdog?.invalidate()
            notches.forEach { $0.panel.close() }
            notches = []
            return
        }
        guard notches.isEmpty else { return }
        notchesOnAllDisplays = settings.allDisplays
        notches = (settings.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))).map(makeNotch)

        // Hover tracking can't see through a window that ignores the mouse, so watch the pointer.
        var lastInside = [Date](repeating: .distantPast, count: notches.count)
        var tick = 0
        var barScreens = NSScreen.screens
        let watchdog = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Listing windows is too costly for every tick; twice a second is plenty.
            tick += 1
            if tick % 15 == 0 { barScreens = Self.screensShowingMenuBar() }
            let pointer = NSEvent.mouseLocation

            for (index, notch) in self.notches.enumerated() {
                let hidden = self.settings.hideNotchInFullScreen && !barScreens.contains(notch.screen)
                if hidden == notch.panel.isVisible { hidden ? notch.panel.orderOut(nil) : notch.panel.orderFrontRegardless() }

                // At the very top the pointer sits exactly on the screen's upper edge,
                // which a rect excludes, so let the region reach past it.
                var region = notch.state.expanded ? notch.expanded : notch.collapsed
                region.size.height += 50
                let inside = !hidden && self.model.track != nil && (region.contains(pointer) || notch.state.pinned)
                if inside { lastInside[index] = Date() }
                // Leaving has to last a moment so skimming the edge doesn't flicker it shut.
                let open = inside || (notch.state.expanded && Date().timeIntervalSince(lastInside[index]) < 0.15)
                guard notch.state.expanded != open else { continue }
                notch.panel.ignoresMouseEvents = !open
                withAnimation(.spring(duration: 0.3)) { notch.state.expanded = open }
            }
        }
        RunLoop.main.add(watchdog, forMode: .common)  // keeps running while a slider is dragged
        notchWatchdog = watchdog
    }

    private func makeNotch(on screen: NSScreen) -> Notch {
        // Screens without a camera housing get a pill of the same size instead.
        var notchWidth = 180.0
        var hasNotch = false
        // Match the menu bar exactly so the pill never hangs over the window below it.
        var height = screen.frame.maxY - screen.visibleFrame.maxY
        if height <= 0 { height = NSStatusBar.system.thickness }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           screen.safeAreaInsets.top > 0 {
            notchWidth = screen.frame.width - left.width - right.width
            height = screen.safeAreaInsets.top
            hasNotch = true
        }
        func frame(_ size: CGSize) -> NSRect {
            NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                   width: size.width, height: size.height)
        }
        let collapsed = frame(CGSize(width: notchWidth + NotchView.wing * 2, height: height))
        let expanded = frame(NotchView.expandedSize(notchWidth: notchWidth, collapsedHeight: height, hasNotch: hasNotch))

        let state = NotchState()
        let panel = makePanel(NotchView(model: model, state: state, notchWidth: notchWidth, collapsedHeight: height,
                                        hasNotch: hasNotch))
        panel.hasShadow = false
        panel.level = .statusBar + 1
        // The window stays at its expanded size and only the view inside animates:
        // resizing the window on hover made the open animation snap. While collapsed
        // it ignores the mouse so the transparent area doesn't block what's beneath.
        panel.setFrame(expanded, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        return Notch(panel: panel, state: state, screen: screen, collapsed: collapsed, expanded: expanded)
    }
}
