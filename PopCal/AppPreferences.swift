import Foundation
import AppKit

/// Where clicking a day in the calendar takes you.
enum CalendarDestination: String, CaseIterable, Identifiable {
    case system
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Calendar app"
        case .google: return "Google Calendar"
        }
    }
}

class AppPreferences: ObservableObject {
    static let shared = AppPreferences()

    @Published var weekStartsOnMonday: Bool {
        didSet { UserDefaults.standard.set(weekStartsOnMonday, forKey: "weekStartsOnMonday") }
    }

    @Published var hotkeyEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled")
            reregisterHotKey()
        }
    }

    @Published var hotkeyKeyCode: Int {
        didSet {
            UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode")
            reregisterHotKey()
        }
    }

    @Published var hotkeyModifiers: NSEvent.ModifierFlags {
        didSet {
            UserDefaults.standard.set(hotkeyModifiers.rawValue, forKey: "hotkeyModifiers")
            reregisterHotKey()
        }
    }

    @Published var calendarDestination: CalendarDestination {
        didSet { UserDefaults.standard.set(calendarDestination.rawValue, forKey: "calendarDestination") }
    }

    @Published var showWeekNumbers: Bool {
        didSet { UserDefaults.standard.set(showWeekNumbers, forKey: "showWeekNumbers") }
    }

    /// Default global hotkey: ⌥⌘C.
    static let defaultHotkeyKeyCode = 8 // C
    static let defaultHotkeyModifiers: NSEvent.ModifierFlags = [.command, .option]

    private init() {
        weekStartsOnMonday = UserDefaults.standard.object(forKey: "weekStartsOnMonday") as? Bool ?? false
        hotkeyEnabled = UserDefaults.standard.object(forKey: "hotkeyEnabled") as? Bool ?? true
        hotkeyKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? Self.defaultHotkeyKeyCode
        let rawMods = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? UInt ?? Self.defaultHotkeyModifiers.rawValue
        hotkeyModifiers = NSEvent.ModifierFlags(rawValue: rawMods)
        showWeekNumbers = UserDefaults.standard.object(forKey: "showWeekNumbers") as? Bool ?? false
        calendarDestination = UserDefaults.standard.string(forKey: "calendarDestination")
            .flatMap(CalendarDestination.init(rawValue:)) ?? .system
    }

    var hotkeyDisplayString: String {
        var parts: [String] = []
        if hotkeyModifiers.contains(.control) { parts.append("⌃") }
        if hotkeyModifiers.contains(.option)  { parts.append("⌥") }
        if hotkeyModifiers.contains(.shift)   { parts.append("⇧") }
        if hotkeyModifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(hotkeyKeyCode))
        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: Int) -> String {
        let map: [Int: String] = [
            49: "Space", 36: "Return", 48: "Tab",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
            22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        ]
        return map[keyCode] ?? "?"
    }

    private func reregisterHotKey() {
        DispatchQueue.main.async {
            if let delegate = NSApp.delegate as? AppDelegate {
                delegate.registerHotKey()
            }
        }
    }
}
