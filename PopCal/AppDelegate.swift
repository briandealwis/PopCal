import AppKit
import SwiftUI
import Carbon

extension Notification.Name {
    /// Posted just before the calendar popover is shown.
    static let popCalWillShow = Notification.Name("PopCalWillShow")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var hotKeyRef: EventHotKeyRef?
    var eventHandler: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupPopover()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotKey()
    }

    // MARK: - Status Item

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }

        button.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "PopCal")
        button.image?.isTemplate = true
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        if event.type == .rightMouseUp || (event.modifierFlags.contains(.command)) {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    func showContextMenu() {
        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit PopCal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    // MARK: - Popover

    func setupPopover() {
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 320)
        popover?.behavior = .transient
        popover?.animates = true
        popover?.contentViewController = CalendarHostingController(rootView: CalendarView())
        NotificationCenter.default.addObserver(self, selector: #selector(focusPopover),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            presentPopover(popover, from: sender)
        }
    }

    func showPopover() {
        guard let popover = popover, !popover.isShown,
              let button = statusItem?.button else { return }
        presentPopover(popover, from: button)
    }

    /// Activates PopCal before showing the popover and making it key, so key
    /// presses (arrows, Return, Esc…) go to the popover rather than the app
    /// that was in front. On macOS 14+ activation is cooperative, so it must
    /// be requested first; `activate(ignoringOtherApps:)` is ignored there.
    private func presentPopover(_ popover: NSPopover, from button: NSStatusBarButton) {
        NotificationCenter.default.post(name: .popCalWillShow, object: nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        focusPopover()
    }

    /// Makes the popover's window key. Also called when PopCal finishes
    /// activating, in case activation completed after the popover appeared.
    @objc func focusPopover() {
        guard let popover = popover, popover.isShown,
              let window = popover.contentViewController?.view.window else { return }
        window.makeKey()
    }

    // MARK: - Settings

    @objc func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let controller = NSHostingController(rootView: settingsView)
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "PopCal Settings"
            settingsWindow?.contentViewController = controller
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Global Hotkey

    func registerHotKey() {
        unregisterHotKey()

        let prefs = AppPreferences.shared
        guard prefs.hotkeyEnabled else { return }

        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x504F_5043) // 'POPC'
        gMyHotKeyID.id = 1

        let keyCode = UInt32(prefs.hotkeyKeyCode)
        var modifiers: UInt32 = 0
        if prefs.hotkeyModifiers.contains(.command)  { modifiers |= UInt32(cmdKey) }
        if prefs.hotkeyModifiers.contains(.option)   { modifiers |= UInt32(optionKey) }
        if prefs.hotkeyModifiers.contains(.control)  { modifiers |= UInt32(controlKey) }
        if prefs.hotkeyModifiers.contains(.shift)    { modifiers |= UInt32(shiftKey) }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            guard let delegate = userData.map({ Unmanaged<AppDelegate>.fromOpaque($0).takeUnretainedValue() }) else {
                return OSStatus(eventNotHandledErr)
            }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if hkID.id == 1 {
                DispatchQueue.main.async { delegate.showPopover() }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        RegisterEventHotKey(keyCode, modifiers, gMyHotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregisterHotKey() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        if let handler = eventHandler { RemoveEventHandler(handler) }
        eventHandler = nil
    }
}

/// Hosts the calendar. Esc in the popover's window sends cancelOperation(_:)
/// up the responder chain; close the popover when it gets here. (CalendarView
/// also handles Esc directly.)
final class CalendarHostingController: NSHostingController<CalendarView> {
    override func cancelOperation(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.popover?.performClose(sender)
    }
}
