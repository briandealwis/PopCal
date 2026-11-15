import XCTest
import SwiftUI
@testable import PopCal

/// Renders PopCal's views to PNGs for the README.
///
/// Skipped unless `POPCAL_SCREENSHOT_DIR` is set; `./build.sh screenshots`
/// sets it (as `TEST_RUNNER_POPCAL_SCREENSHOT_DIR`, which xcodebuild passes
/// to the test process). Views are drawn offscreen, so this needs no
/// Screen Recording permission.
final class ScreenshotTests: XCTestCase {

    private var outputDirectory: URL!
    private var savedWeekStartsOnMonday = false

    /// A fixed "today" so screenshots only change when the UI does.
    static let showcaseDate: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!
    }()

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["POPCAL_SCREENSHOT_DIR"], !path.isEmpty else {
            throw XCTSkip("Set POPCAL_SCREENSHOT_DIR (or run ./build.sh screenshots) to generate screenshots")
        }
        outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        savedWeekStartsOnMonday = AppPreferences.shared.weekStartsOnMonday
        AppPreferences.shared.weekStartsOnMonday = false
    }

    override func tearDown() {
        if outputDirectory != nil {
            AppPreferences.shared.weekStartsOnMonday = savedWeekStartsOnMonday
        }
        super.tearDown()
    }

    @MainActor
    func testCalendarLight() throws {
        try snapshot(CalendarView(now: Self.showcaseDate), dark: false, name: "calendar-light")
    }

    @MainActor
    func testCalendarDark() throws {
        try snapshot(CalendarView(now: Self.showcaseDate), dark: true, name: "calendar-dark")
    }

    @MainActor
    func testSettings() throws {
        try snapshot(SettingsView(), dark: false, name: "settings")
    }

    // MARK: - Rendering

    @MainActor
    private func snapshot<V: View>(_ view: V, dark: Bool, name: String, scale: CGFloat = 2) throws {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let framed = view
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
            .environment(\.colorScheme, dark ? .dark : .light)

        let hostingView = NSHostingView(rootView: framed)
        hostingView.appearance = appearance
        let size = hostingView.fittingSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hostingView.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Let SwiftUI lay out and render.
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        appearance.performAsCurrentDrawingAppearance {
            hostingView.cacheDisplay(in: hostingView.bounds, to: rep)
        }

        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("Wrote screenshot \(url.path)")
    }
}
