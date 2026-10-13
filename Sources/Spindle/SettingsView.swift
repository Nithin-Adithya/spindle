import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Every setting in one window, each with a line saying what it does.
struct SettingsView: View {
    @ObservedObject var model: MusicViewModel
    @ObservedObject var settings = Settings.shared
    @ObservedObject var hotKeys = HotKeyCenter.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        TabView {
            Form { general }.formStyle(.grouped).tabItem { Label("General", systemImage: "gearshape") }
            Form { notch }.formStyle(.grouped).tabItem { Label("Notch", systemImage: "capsule.tophalf.filled") }
            Form { widget }.formStyle(.grouped).tabItem { Label("Widget", systemImage: "rectangle.on.rectangle") }
            Form { shortcuts }.formStyle(.grouped).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            Form { guide }.formStyle(.grouped).tabItem { Label("Guide", systemImage: "questionmark.circle") }
        }
        .frame(width: 540, height: 540)
    }

    @ViewBuilder private var general: some View {
        Section("App") {
            Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                Text("Launch at login")
                Text(loginError ?? L("Starts Spindle when you log in to your Mac."))
            }
            row("Show in menu bar", "The disc icon that opens the player. If you hide it, open Spindle "
                + "again from Finder or Spotlight to get back to these settings.", isOn: $settings.showMenuBarIcon)
            row("Show Dock icon", "Off keeps Spindle out of the Dock and the app switcher.", isOn: $settings.showDockIcon)
            row("Show artwork in Dock", "Uses the current cover as the Dock icon.", isOn: $settings.artworkInDock)
                .disabled(!settings.showDockIcon)
        }
        Section("Music") {
            Picker(selection: $settings.source) {
                ForEach(SourcePreference.allCases) { Text($0.label).tag($0) }
            } label: {
                Text("Music source")
                Text("Automatic follows whichever of Spotify and Apple Music is playing.")
            }
            row("Show time remaining", "The time on the right of the seek bar counts down instead of showing the track's length.",
                isOn: $settings.timeCountsDown)
            Picker(selection: Binding(get: { sleepMinutes }, set: setSleep)) {
                Text("Off").tag(0)
                ForEach([5, 15, 30, 45, 60, 90], id: \.self) { Text("\($0) minutes").tag($0) }
            } label: {
                Text("Sleep timer")
                Text(sleepCaption)
            }
        }
        Section("Appearance") {
            row("Album color", "Tints the popover and widget with the cover's color. Off uses dark grey.",
                isOn: $settings.useAlbumColor)
            Picker("Record style", selection: $settings.vinylStyle) {
                ForEach(VinylStyle.allCases) { Text($0.label).tag($0) }
            }
            Picker("Player size", selection: $settings.playerSize) {
                ForEach(WidgetSize.allCases) { Text($0.label).tag($0) }
            }
        }
    }

    @ViewBuilder private var notch: some View {
        Section {
            row("Notch display", "A pill at the top centre of the screen showing the cover and bars. "
                + "Hover it to open a player with controls.", isOn: $settings.showNotch)
            row("Hide in full screen", "Removes the pill while an app is full screen on that display.",
                isOn: $settings.hideNotchInFullScreen)
                .disabled(!settings.showNotch)
        }
        Section("Style") {
            ForEach(NotchStyle.available) { style in
                choice(style.label, style.detail, selected: settings.notchStyle == style) { settings.notchStyle = style }
            }
            if NotchStyle.available.count == 1 {
                Text("Glass styles need macOS 26 or later.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .disabled(!settings.showNotch)
    }

    @ViewBuilder private var widget: some View {
        Section {
            row("Desktop widget", "A card on the desktop with the record and controls. Drag it anywhere.",
                isOn: $settings.showWidget)
            Picker(selection: $settings.widgetLevel) {
                ForEach(WidgetLevel.allCases) { Text($0.label).tag($0) }
            } label: {
                Text("Window behavior")
                Text("Below keeps it on the desktop under everything; above floats it over other windows.")
            }
        }
        Section("Theme") {
            ForEach(WidgetTheme.allCases) { theme in
                choice(theme.label, theme.detail, selected: settings.widgetTheme == theme) { settings.widgetTheme = theme }
            }
            Picker("Size", selection: $settings.widgetSize) {
                ForEach(WidgetSize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Font", selection: $settings.widgetFont) {
                ForEach(WidgetFont.allCases) { Text($0.label).tag($0) }
            }
            ColorPicker("Title color", selection: hexBinding(\.widgetTitleColor), supportsOpacity: false)
            Picker("Title size", selection: $settings.widgetTitleSize) {
                ForEach(TextSize.allCases) { Text($0.label).tag($0) }
            }
            Picker("Subtitle size", selection: $settings.widgetSubtitleSize) {
                ForEach(TextSize.allCases) { Text($0.label).tag($0) }
            }
        }
        Section("Background") {
            Picker("Background", selection: $settings.widgetBackground) {
                ForEach(WidgetBackground.available) { Text($0.label).tag($0) }
            }
            if settings.widgetBackground == .color {
                ColorPicker("Color", selection: hexBinding(\.widgetColor), supportsOpacity: false)
            }
            if settings.widgetBackground == .image {
                LabeledContent(settings.widgetImagePath.isEmpty ? L("No image chosen")
                               : (settings.widgetImagePath as NSString).lastPathComponent) {
                    Button("Choose…", action: chooseImage)
                }
            }
            row("Shadow", "A soft shadow under the widget. Transparent backgrounds never have one.",
                isOn: $settings.widgetShadow)
        }
        Section("Details") {
            row("Show stylus", "The tonearm that swings onto the record while music plays.", isOn: $settings.widgetStylus)
            row("Show progress", "The seek bar and times.", isOn: $settings.widgetProgress)
        }
        Section("Desktop") {
            row("Cover art as wallpaper", "Replaces your desktop picture with the current cover on every display. "
                + "Your own picture comes back when you turn this off or quit Spindle.", isOn: $settings.coverAsWallpaper)
        }
    }

    @ViewBuilder private var guide: some View {
        Section("Supported music services") {
            Text(L("Spotify and Apple Music, through their Mac apps. Music playing in a browser is not supported yet."))
        }
        Section("Permission") {
            Text(L("The first time a player is open, macOS asks whether Spindle may control it. Choose Allow. "
                + "If you chose Don't Allow, turn it back on under Privacy & Security, Automation."))
            Button(L("Open Automation Settings")) {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        Section("Tips") {
            Text(L("Hover the pill at the top of the screen to open it, and move away to close it."))
            Text(L("Drag the desktop widget anywhere; it remembers where you left it."))
            Text(L("Click the disc in the menu bar for the player, or open Spindle again for the full window."))
        }
    }

    private func choice(_ title: String, _ detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hexBinding(_ keyPath: ReferenceWritableKeyPath<Settings, String>) -> Binding<Color> {
        Binding(get: { Color(hex: settings[keyPath: keyPath]) }, set: { settings[keyPath: keyPath] = $0.hex })
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url { settings.widgetImagePath = url.path }
    }

    @ViewBuilder private var shortcuts: some View {
        Section {
            ForEach(HotKeyAction.allCases) { action in
                LabeledContent(action.label) {
                    ShortcutRecorder(combo: hotKeys.combos[action]) { hotKeys.set($0, for: action) }
                }
            }
        } footer: {
            Text(L("Shortcuts work in any app. Click one, then press the keys; they must include ⌘, ⌥ or ⌃. "
                + "Press Delete to clear, Esc to cancel."))
        }
    }

    private func row(_ title: String, _ detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(L(title))
            Text(L(detail))
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = String(format: L("Could not change this: %@"), error.localizedDescription)
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var sleepMinutes: Int {
        guard let deadline = model.sleepDeadline else { return 0 }
        // Snap back to the option that was picked while it counts down.
        let remaining = deadline.timeIntervalSinceNow / 60
        return [5, 15, 30, 45, 60, 90].first { Double($0) >= remaining } ?? 90
    }

    private func setSleep(_ minutes: Int) {
        model.sleepDeadline = minutes == 0 ? nil : Date().addingTimeInterval(Double(minutes) * 60)
    }

    private var sleepCaption: String {
        guard let deadline = model.sleepDeadline else { return L("Pauses the music after a set time.") }
        // `position` ticks every second, which keeps this caption counting down.
        _ = model.position
        let minutes = max(1, Int((deadline.timeIntervalSinceNow / 60).rounded(.up)))
        return String(format: L("Pauses the music in %d min."), minutes)
    }
}

/// A button that captures the next key combination pressed while it is armed.
private struct ShortcutRecorder: View {
    let combo: KeyCombo?
    let onChange: (KeyCombo?) -> Void

    @State private var monitor: Any?

    var body: some View {
        Button(monitor != nil ? L("Press keys…") : combo?.display ?? L("Record")) {
            monitor == nil ? start() : stop()
        }
        .frame(minWidth: 110, alignment: .trailing)
        .onDisappear(perform: stop)
    }

    private func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if event.keyCode == 51 {  // Delete
                onChange(nil)
                stop()
            } else if let combo = KeyCombo(event: event) {
                onChange(combo)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
