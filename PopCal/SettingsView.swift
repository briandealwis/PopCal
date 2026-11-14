import SwiftUI
import Carbon

struct SettingsView: View {
    @StateObject private var prefs = AppPreferences.shared
    @State private var isRecordingHotkey = false
    @State private var monitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
                Text("PopCal")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Calendar section
                    settingsSection(title: "Calendar") {
                        VStack(spacing: 10) {
                            settingsRow(label: "Week starts on") {
                                Picker("", selection: $prefs.weekStartsOnMonday) {
                                    Text("Sunday").tag(false)
                                    Text("Monday").tag(true)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                            }
                        }
                    }

                    // Hotkey section
                    settingsSection(title: "Global Hotkey") {
                        VStack(spacing: 10) {
                            settingsRow(label: "Enable hotkey") {
                                Toggle("", isOn: $prefs.hotkeyEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }

                            if prefs.hotkeyEnabled {
                                settingsRow(label: "Shortcut") {
                                    HStack(spacing: 6) {
                                        if isRecordingHotkey {
                                            Text("Press a key…")
                                                .font(.system(size: 12, design: .monospaced))
                                                .foregroundColor(.accentColor)
                                                .frame(width: 120, height: 24)
                                                .background(Color.accentColor.opacity(0.1))
                                                .cornerRadius(5)
                                        } else {
                                            Text(prefs.hotkeyDisplayString)
                                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                                .padding(.horizontal, 8)
                                                .frame(height: 24)
                                                .background(Color(nsColor: .controlBackgroundColor))
                                                .cornerRadius(5)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 5)
                                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                                )
                                        }

                                        Button(isRecordingHotkey ? "Cancel" : "Record") {
                                            if isRecordingHotkey {
                                                stopRecording()
                                            } else {
                                                startRecording()
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Text("Tip: Right-click or ⌘-click the menubar icon for this menu")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 380, height: 260)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { stopRecording() }
    }

    // MARK: - Helpers

    @ViewBuilder
    func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .kerning(0.8)

            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    func settingsRow<Content: View>(label: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            trailing()
        }
    }

    // MARK: - Hotkey Recording

    func startRecording() {
        isRecordingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            self.handleKeyEvent(event)
            return nil
        }
    }

    func stopRecording() {
        isRecordingHotkey = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode != 53 else { // Escape
            stopRecording()
            return
        }
        prefs.hotkeyKeyCode = Int(event.keyCode)
        prefs.hotkeyModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        stopRecording()
    }
}
