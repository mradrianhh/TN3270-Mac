import AppKit
import XCTest
import TN3270Core
@testable import TN3270Mac

final class TerminalLayoutTests: XCTestCase {
    private func assertGridFits(_ view: TerminalNSView, rows: Int, columns: Int,
                                file: StaticString = #filePath, line: UInt = #line) {
        let metrics = view.computeMetrics(rows: rows, columns: columns)
        let grid = CGRect(x: metrics.origin.x, y: metrics.origin.y,
                          width: CGFloat(columns) * metrics.cellWidth,
                          height: CGFloat(rows) * metrics.cellHeight)
        let available = view.safeAreaRect.insetBy(dx: 4, dy: 4)
        XCTAssertGreaterThanOrEqual(grid.minX, available.minX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(grid.minY, available.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(grid.maxX, available.maxX, file: file, line: line)
        XCTAssertLessThanOrEqual(grid.maxY, available.maxY, file: file, line: line)
    }

    func testAllTerminalModelsFitAtMinimumAndScreenshotSizes() {
        for size in [NSSize(width: 720, height: 420), NSSize(width: 944, height: 710)] {
            let view = TerminalNSView(frame: NSRect(origin: .zero, size: size))
            for model in TerminalModel.allCases {
                assertGridFits(view, rows: model.rows, columns: model.columns)
            }
        }
    }

    func testHeightFitIncludesPerRowRounding() {
        let rows = TerminalModel.model4.rows
        let columns = TerminalModel.model4.columns
        for size in 10...30 {
            let font = NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
            let width = ("W" as NSString).size(withAttributes: [.font: font]).width
            let height = ((font.ascender - font.descender + font.leading) * 1.1).rounded(.up)
            let view = TerminalNSView(frame: NSRect(
                x: 0, y: 0, width: CGFloat(columns) * width + 100,
                height: CGFloat(rows) * height + 7))
            assertGridFits(view, rows: rows, columns: columns)
        }
    }

    func testGridFitsBelowFullSizeWindowTitleBar() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 944, height: 746),
                              styleMask: [.titled, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let view = TerminalNSView(frame: window.contentView!.bounds)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThan(view.safeAreaRect.height, view.bounds.height)
        assertGridFits(view, rows: TerminalModel.model4.rows, columns: TerminalModel.model4.columns)
    }

    func testYellowFieldsRenderWithBlackSeparatorOnLastRow() throws {
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let screen = model.session.screen
        let rowStart = (screen.rows - 1) * screen.columns
        let field: [UInt8] = [0x29, 0x03, 0xC0, 0x60, 0x42, 0xF6, 0x41, 0xF2]
        model.session.processor.process(
            [0xF5, 0xC3, 0x11] + DS.encodeAddress(rowStart, bufferSize: screen.size)
            + field + model.session.codePage.encode("-TNFPROD")
            + field + model.session.codePage.encode("*TNFPROD") + [0x1D, 0x60])
        let view = TerminalNSView(frame: NSRect(x: 0, y: 0, width: 944, height: 710))
        view.model = model
        let metrics = view.computeMetrics(rows: screen.rows, columns: screen.columns)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        for column in [1, 9, 10] {
            let x = metrics.origin.x + (CGFloat(column) + 0.5) * metrics.cellWidth
            let y = metrics.origin.y + CGFloat(screen.rows) * metrics.cellHeight - 1
            let color = try XCTUnwrap(bitmap.colorAt(
                x: Int(x * CGFloat(bitmap.pixelsWide) / view.bounds.width),
                y: Int(y * CGFloat(bitmap.pixelsHigh) / view.bounds.height))?.usingColorSpace(.deviceRGB))
            let expected = try XCTUnwrap(
                (column == 9 ? NSColor.black : TerminalNSView.color(.yellow)).usingColorSpace(.deviceRGB))
            XCTAssertEqual(color.redComponent, expected.redComponent, accuracy: 0.02)
            XCTAssertEqual(color.greenComponent, expected.greenComponent, accuracy: 0.02)
            XCTAssertEqual(color.blueComponent, expected.blueComponent, accuracy: 0.02)
        }
    }
}
