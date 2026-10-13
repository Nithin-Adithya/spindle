import AppKit
import Carbon.HIToolbox

enum HotKeyAction: String, CaseIterable, Identifiable {
    case playPause, next, previous, togglePopover, toggleNotch, toggleMenuBarIcon

    var id: String { rawValue }

    var label: String {
        switch self {
        case .playPause: return L("Play/pause")
        case .next: return L("Next track")
        case .previous: return L("Previous track")
        case .togglePopover: return L("Toggle popover")
        case .toggleNotch: return L("Toggle notch open")
        case .toggleMenuBarIcon: return L("Toggle menu bar icon")
        }
    }
}

/// A recorded key combination. `display` is kept alongside because turning a
/// key code back into the character on the user's layout is not worth the code.
struct KeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32  // Carbon flags
    var display: String

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Without one of these the shortcut would swallow ordinary typing everywhere.
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        display = symbols + Self.keyName(event)
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return L("Space")
        case kVK_Return: return "↩"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3, let code = UInt32(parts[0]), let mods = UInt32(parts[1]) else { return nil }
        (keyCode, modifiers, display) = (code, mods, parts[2])
    }

    var stored: String { "\(keyCode):\(modifiers):\(display)" }
}

/// System-wide shortcuts through Carbon hot keys, which need no accessibility permission.
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    @Published private(set) var combos: [HotKeyAction: KeyCombo] = [:]
    var handler: (HotKeyAction) -> Void = { _ in }

    private var refs: [EventHotKeyRef] = []

    private init() {
        for action in HotKeyAction.allCases {
            if let stored = UserDefaults.standard.string(forKey: "hotkey." + action.rawValue) {
                combos[action] = KeyCombo(stored: stored)
            }
        }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let index = Int(id.id)
            if HotKeyAction.allCases.indices.contains(index) {
                HotKeyCenter.shared.handler(HotKeyAction.allCases[index])
            }
            return noErr
        }, 1, &spec, nil, nil)
        register()
    }

    func set(_ combo: KeyCombo?, for action: HotKeyAction) {
        // One combination can only drive one action.
        if let combo {
            for (other, existing) in combos where other != action && existing.keyCode == combo.keyCode
                && existing.modifiers == combo.modifiers {
                combos[other] = nil
                UserDefaults.standard.removeObject(forKey: "hotkey." + other.rawValue)
            }
        }
        combos[action] = combo
        UserDefaults.standard.set(combo?.stored, forKey: "hotkey." + action.rawValue)
        register()
    }

    private func register() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        for (index, action) in HotKeyAction.allCases.enumerated() {
            guard let combo = combos[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x5350_4E44), id: UInt32(index))  // 'SPND'
            if RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &ref) == noErr,
               let ref {
                refs.append(ref)
            }
        }
    }
}
