import AppKit
import XCTest
import TN3270Core
@testable import TN3270Mac

final class TerminalSelectionTests: XCTestCase {
    private func fixture() -> (AppModel, TerminalNSView) {
        let model = AppModel(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        // Block selection is the default; most tests here exercise linear selection.
        model.blockSelection = false
        model.session.processor.screen.clear(rows: 3, columns: 4)
        for (address, byte) in model.session.codePage.encode("ABCDEFGHIJKL").enumerated() {
            model.session.processor.screen[address].byte = byte
        }
        // These dimensions give 100-point font metrics and a four-point inset.
        let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        let height = ((font.ascender - font.descender + font.leading) * 1.1).rounded(.up)
        let view = TerminalNSView(frame: NSRect(x: 0, y: 0, width: width * 4 + 8, height: height * 3 + 8))
        view.model = model
        return (model, view)
    }

    private func arrow(_ code: UInt16, in view: TerminalNSView, modifiers: NSEvent.ModifierFlags = .shift) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "",
                                    charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        view.keyDown(with: event)
    }

    private func mouse(_ type: NSEvent.EventType, boundary: Int, in view: TerminalNSView,
                       modifierFlags: NSEvent.ModifierFlags = []) {
        let font = NSFont.monospacedSystemFont(ofSize: 100, weight: .regular)
        let width = ("W" as NSString).size(withAttributes: [.font: font]).width
        let height = ((font.ascender - font.descender + font.leading) * 1.1).rounded(.up)
        let point = NSPoint(x: 4 + CGFloat(boundary % 4) * width,
                            y: 4 + (CGFloat(boundary / 4) + 0.25) * height)
        let event = NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: modifierFlags,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      eventNumber: 0, clickCount: 1, pressure: 1)!
        if type == .leftMouseDown { view.mouseDown(with: event) } else { view.mouseDragged(with: event) }
    }

    func testShiftArrowsExtendShrinkAndReverseWithoutMovingHostCursor() {
        let (model, view) = fixture()
        model.session.moveCursor(to: 2)
        arrow(124, in: view)
        XCTAssertEqual(view.selectedText, "C")
        arrow(125, in: view)
        XCTAssertEqual(view.selectedText, "CD\nEFG")
        arrow(126, in: view)
        arrow(123, in: view)
        XCTAssertNil(view.selectedText)
        arrow(123, in: view)
        XCTAssertEqual(view.selectedText, "B")
        XCTAssertEqual(model.session.screen.cursor, 2)
    }

    func testSelectionStopsAtScreenEdgesAndResetsAfterTypingOrResize() {
        let (model, view) = fixture()
        arrow(123, in: view)
        XCTAssertNil(view.selectedText)
        mouse(.leftMouseDown, boundary: 11, in: view)
        arrow(125, in: view)
        arrow(124, in: view)
        XCTAssertEqual(view.selectedText, "L")
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "a",
                                    charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        view.keyDown(with: event)
        XCTAssertNil(view.selectedText)
        arrow(124, in: view)
        XCTAssertNotNil(view.selectedText)
        model.session.processor.screen.clear(rows: 2, columns: 4)
        XCTAssertNil(view.selectedText)
    }

    func testMouseDragSelectsAcrossRowsInEitherDirectionAndClickClears() {
        let (model, view) = fixture()
        mouse(.leftMouseDown, boundary: 1, in: view)
        mouse(.leftMouseDragged, boundary: 6, in: view)
        XCTAssertEqual(view.selectedText, "BCD\nEF")
        XCTAssertEqual(model.session.screen.cursor, 1)
        mouse(.leftMouseDown, boundary: 6, in: view)
        mouse(.leftMouseDragged, boundary: 1, in: view)
        XCTAssertEqual(view.selectedText, "BCD\nEF")
        arrow(124, in: view)
        XCTAssertEqual(view.selectedText, "CD\nEF")
        mouse(.leftMouseDown, boundary: 0, in: view)
        XCTAssertNil(view.selectedText)
    }

    func testBlockMouseSelectionViaToggleWorksInEitherDirection() {
        let (model, view) = fixture()
        model.blockSelection = true
        mouse(.leftMouseDown, boundary: 1, in: view)
        mouse(.leftMouseDragged, boundary: 11, in: view)
        XCTAssertEqual(view.selectedText, "BC\nFG\nJK")

        mouse(.leftMouseDown, boundary: 11, in: view)
        mouse(.leftMouseDragged, boundary: 1, in: view)
        XCTAssertEqual(view.selectedText, "BC\nFG\nJK")
    }

    func testOptionInvertsMouseSelectionMode() {
        let (model, view) = fixture()
        mouse(.leftMouseDown, boundary: 1, in: view, modifierFlags: .option)
        mouse(.leftMouseDragged, boundary: 11, in: view)
        XCTAssertEqual(view.selectedText, "BC\nFG\nJK")

        model.blockSelection = true
        mouse(.leftMouseDown, boundary: 1, in: view, modifierFlags: .option)
        mouse(.leftMouseDragged, boundary: 11, in: view)
        XCTAssertEqual(view.selectedText, "BCD\nEFGH\nIJK")
    }

    func testShiftArrowsExtendBlockSelectionByRowAndColumn() {
        let (model, view) = fixture()
        model.blockSelection = true
        model.session.moveCursor(to: 1)
        arrow(124, in: view)
        arrow(125, in: view)
        arrow(125, in: view)
        XCTAssertEqual(view.selectedText, "B\nF\nJ")
        arrow(123, in: view)
        XCTAssertNil(view.selectedText)
    }

    func testBlockSelectionIsDefaultAndPreferenceIsPersisted() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(defaults: defaults)
        XCTAssertTrue(model.blockSelection)
        model.blockSelection = false
        XCTAssertFalse(AppModel(defaults: defaults).blockSelection)
    }

    func testSelectionDoesNotExposeNonDisplayFields() {
        let (model, view) = fixture()
        model.session.processor.screen[0].isFieldAttribute = true
        model.session.processor.screen[0].byte = DS.FieldAttribute.nonDisplay
        arrow(125, in: view)
        XCTAssertEqual(view.selectedText, "    ")
    }

    func testShiftArrowsAreLocalEvenWhenMappedAndPlainArrowsStillMoveCursor() {
        let (model, view) = fixture()
        model.keyMap.bind(KeyStroke(KeyStroke.Named.right, .shift), to: .clear)
        arrow(124, in: view)
        XCTAssertEqual(view.selectedText, "A")
        XCTAssertEqual(model.session.screen.cursor, 0)
        arrow(124, in: view, modifiers: [])
        XCTAssertNil(view.selectedText)
        XCTAssertEqual(model.session.screen.cursor, 1)
    }

    func testCopyUsesSelectedTextAndFallsBackToWholeScreen() {
        let (model, view) = fixture()
        defer { withExtendedLifetime(model) {} }
        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let saved = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { saved.setData(data, forType: type) }
            }
            return saved
        }
        defer {
            pasteboard.clearContents()
            pasteboard.writeObjects(savedItems)
        }
        arrow(124, in: view)
        arrow(124, in: view)
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "c",
                                    charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
        view.keyDown(with: event)
        XCTAssertEqual(pasteboard.string(forType: .string), "AB")
        arrow(124, in: view, modifiers: [])
        view.copy(nil)
        XCTAssertEqual(pasteboard.string(forType: .string), "ABCD\nEFGH\nIJKL")
    }
}
