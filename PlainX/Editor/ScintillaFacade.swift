//
//  ScintillaFacade.swift
//  PlainX Editor
//
//  The single place in the Swift codebase that references raw Scintilla
//  message IDs and style constants. Everything else talks to the editor
//  through this typed facade.
//
//  Threading: all members must be used on the main thread (AppKit rule).
//  ScintillaView is not thread-safe.
//

import AppKit

// MARK: - Modification events (for text sync, macros, dirty tracking)

struct ScintillaModification {
    var position: Int
    var length: Int
    var linesAdded: Int
    var modificationType: Int
    /// Inserted text (only populated for SC_MOD_INSERTTEXT).
    var insertedText: String?

    var isInsertText: Bool { modificationType & Int(SC_MOD_INSERTTEXT) != 0 }
    var isDeleteText: Bool { modificationType & Int(SC_MOD_DELETETEXT) != 0 }
    var isBeforeDelete: Bool { modificationType & Int(SC_MOD_BEFOREDELETE) != 0 }
    var isUserAction: Bool { modificationType & Int(SC_PERFORMED_USER) != 0 }
    var isUndo: Bool { modificationType & Int(SC_PERFORMED_UNDO) != 0 }
    var isRedo: Bool { modificationType & Int(SC_PERFORMED_REDO) != 0 }
}

struct EditorSelection {
    var anchor: Int
    var caret: Int

    var lowerBound: Int { min(anchor, caret) }
    var upperBound: Int { max(anchor, caret) }
    var isEmpty: Bool { anchor == caret }
    var length: Int { abs(caret - anchor) }
}

enum ScintillaFoldAction {
    case toggle
    case contract
    case expand
    case contractAll
    case expandAll
}

protocol ScintillaFacadeDelegate: AnyObject {
    func scintillaDidUpdateUI(_ facade: ScintillaFacade)
    func scintillaDidChangeContent(_ facade: ScintillaFacade, modification: ScintillaModification)
    func scintillaDidChangeDirtyState(_ facade: ScintillaFacade, isDirty: Bool)
    func scintillaDidTypeCharacter(_ facade: ScintillaFacade, byte: UInt8)
    func scintillaMarginClicked(_ facade: ScintillaFacade, margin: Int, modifiers: NSEvent.ModifierFlags, position: Int)
}

extension ScintillaFacadeDelegate {
    func scintillaDidUpdateUI(_ facade: ScintillaFacade) {}
    func scintillaDidChangeContent(_ facade: ScintillaFacade, modification: ScintillaModification) {}
    func scintillaDidChangeDirtyState(_ facade: ScintillaFacade, isDirty: Bool) {}
    func scintillaDidTypeCharacter(_ facade: ScintillaFacade, byte: UInt8) {}
    func scintillaMarginClicked(_ facade: ScintillaFacade, margin: Int, modifiers: NSEvent.ModifierFlags, position: Int) {}
}

// MARK: - Facade

final class ScintillaFacade: NSObject, ScintillaNotificationProtocol {
    let view: ScintillaView
    weak var delegate: ScintillaFacadeDelegate?

    /// Set while PlainX itself is applying programmatic edits that should not
    /// be reported as user changes (used by cloned-view sync).
    var isApplyingRemoteEdit = false

    init(view: ScintillaView) {
        self.view = view
        super.init()
        view.delegate = self
    }

    deinit {
        view.delegate = nil
    }

    // MARK: Message plumbing

    @discardableResult
    func send(_ message: Int32) -> Int {
        view.message(UInt32(bitPattern: message))
    }

    @discardableResult
    func send(_ message: Int32, w: Int) -> Int {
        view.message(UInt32(bitPattern: message), wParam: UInt(bitPattern: w))
    }

    @discardableResult
    func send(_ message: Int32, w: Int, l: Int) -> Int {
        view.message(UInt32(bitPattern: message), wParam: UInt(bitPattern: w), lParam: l)
    }

    @discardableResult
    func send(_ message: Int32, w: Int, string: String) -> Int {
        var result = 0
        string.withCString { pointer in
            result = view.message(UInt32(bitPattern: message), wParam: UInt(bitPattern: w),
                                  lParam: Int(bitPattern: pointer))
        }
        return result
    }

    @discardableResult
    func send(_ message: Int32, key: String, value: String) -> Int {
        var result = 0
        key.withCString { keyPointer in
            value.withCString { valuePointer in
                result = view.message(UInt32(bitPattern: message),
                                      wParam: UInt(bitPattern: Int(bitPattern: keyPointer)),
                                      lParam: Int(bitPattern: valuePointer))
            }
        }
        return result
    }

    // MARK: - Text

    var text: String {
        get { view.string() ?? "" }
        set {
            view.setString(newValue)
        }
    }

    var length: Int { send(SCI_GETLENGTH) }
    var lineCount: Int { send(SCI_GETLINECOUNT) }
    var isModified: Bool { send(SCI_GETMODIFY) != 0 }
    var isReadOnly: Bool { send(SCI_GETREADONLY) != 0 }

    func setReadOnly(_ readOnly: Bool) {
        send(SCI_SETREADONLY, w: readOnly ? 1 : 0)
    }

    func character(at position: Int) -> UInt8 {
        UInt8(truncatingIfNeeded: send(SCI_GETCHARAT, w: position))
    }

    func lineStart(_ line: Int) -> Int { send(SCI_POSITIONFROMLINE, w: line) }
    func lineEnd(_ line: Int) -> Int { send(SCI_GETLINEENDPOSITION, w: line) }
    func line(from position: Int) -> Int { send(SCI_LINEFROMPOSITION, w: position) }
    func column(of position: Int) -> Int { send(SCI_GETCOLUMN, w: position) }
    func lineLength(_ line: Int) -> Int { send(SCI_LINELENGTH, w: line) }
    func lineVisible(_ line: Int) -> Bool { send(SCI_GETLINEVISIBLE, w: line) != 0 }
    func pointX(fromPosition position: Int) -> Int { send(SCI_POINTXFROMPOSITION, w: 0, l: position) }
    func pointY(fromPosition position: Int) -> Int { send(SCI_POINTYFROMPOSITION, w: 0, l: position) }
    func position(fromPoint point: NSPoint) -> Int {
        send(SCI_POSITIONFROMPOINT, w: Int(point.x), l: Int(point.y))
    }
    func textHeight(_ line: Int) -> Int { send(SCI_TEXTHEIGHT, w: line) }

    func text(inRange range: NSRange) -> String {
        let start = max(0, range.location)
        let end = min(length, range.location + range.length)
        guard end > start else { return "" }
        let byteCount = end - start
        guard byteCount < 256 * 1024 * 1024 else { return "" }
        return withTextRange(start: start, end: end) ?? ""
    }

    private func withTextRange(start: Int, end: Int) -> String? {
        let capacity = end - start + 1
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: capacity)
        var textRange = Sci_TextRange(
            chrg: Sci_CharacterRange(cpMin: start, cpMax: end),
            lpstrText: buffer
        )
        let copied = withUnsafeMutablePointer(to: &textRange) { pointer -> Int in
            send(SCI_GETTEXTRANGE, w: 0, l: Int(bitPattern: pointer))
        }
        guard copied >= 0 else { return nil }
        return String(cString: buffer)
    }

    func lineText(_ line: Int) -> String {
        guard line >= 0, line < lineCount else { return "" }
        let start = lineStart(line)
        let end = lineEnd(line)
        return text(inRange: NSRange(location: start, length: end - start))
    }

    func insert(text: String, at position: Int) {
        let bytes = text.utf8.count
        guard bytes > 0 else { return }
        guard let pointer = malloc(bytes + 1) else { return }
        defer { free(pointer) }
        _ = text.withCString { source in
            memcpy(pointer, source, bytes + 1)
        }
        send(SCI_INSERTTEXT, w: position, l: Int(bitPattern: pointer))
    }

    func deleteRange(location: Int, length deleteLength: Int) {
        guard deleteLength > 0 else { return }
        send(SCI_DELETERANGE, w: location, l: deleteLength)
    }

    func replace(range: NSRange, with text: String) {
        send(SCI_SETTARGETSTART, w: range.location)
        send(SCI_SETTARGETEND, w: range.location + range.length)
        send(SCI_REPLACETARGET, w: text.utf8.count, string: text)
    }

    func clearAll() {
        send(SCI_CLEARALL)
    }

    // MARK: - Undo / save point

    var canUndo: Bool { send(SCI_CANUNDO) != 0 }
    var canRedo: Bool { send(SCI_CANREDO) != 0 }

    func undo() { send(SCI_UNDO) }
    func redo() { send(SCI_REDO) }
    func emptyUndoBuffer() { send(SCI_EMPTYUNDOBUFFER) }
    func setSavePoint() { send(SCI_SETSAVEPOINT) }
    func beginUndoAction() { send(SCI_BEGINUNDOACTION) }
    func endUndoAction() { send(SCI_ENDUNDOACTION) }
    func setUndoCollection(_ enabled: Bool) { send(SCI_SETUNDOCOLLECTION, w: enabled ? 1 : 0) }

    // MARK: - Selections

    var selectionCount: Int { send(SCI_GETSELECTIONS) }
    var mainSelectionIndex: Int { send(SCI_GETMAINSELECTION) }

    var currentPosition: Int { send(SCI_GETCURRENTPOS) }
    var anchorPosition: Int { send(SCI_GETANCHOR) }

    var mainSelection: EditorSelection {
        EditorSelection(anchor: anchorPosition, caret: currentPosition)
    }

    var selectedRange: NSRange {
        let selection = mainSelection
        if selection.isEmpty { return NSRange(location: selection.caret, length: 0) }
        return NSRange(location: selection.lowerBound, length: selection.length)
    }

    func selectedText() -> String {
        view.selectedString() ?? ""
    }

    func allSelections() -> [EditorSelection] {
        var result: [EditorSelection] = []
        let count = selectionCount
        for index in 0..<count {
            let anchor = send(SCI_GETSELECTIONNANCHOR, w: index)
            let caret = send(SCI_GETSELECTIONNCARET, w: index)
            result.append(EditorSelection(anchor: anchor, caret: caret))
        }
        return result
    }

    func setSelection(anchor: Int, caret: Int) {
        send(SCI_SETSEL, w: anchor, l: caret)
    }

    func selectAll() {
        send(SCI_SELECTALL)
    }

    func setSelections(_ selections: [EditorSelection], mainIndex: Int = 0) {
        guard !selections.isEmpty else { return }
        send(SCI_CLEARSELECTIONS)
        for (index, selection) in selections.enumerated() {
            if index == 0 {
                setSelection(anchor: selection.anchor, caret: selection.caret)
                send(SCI_SETMAINSELECTION, w: 0)
            } else {
                send(SCI_ADDSELECTION, w: selection.caret, l: selection.anchor)
            }
        }
        if mainIndex != 0, mainIndex < selections.count {
            send(SCI_SETMAINSELECTION, w: mainIndex)
        }
    }

    func gotoPosition(_ position: Int) {
        send(SCI_GOTOPOS, w: position)
    }

    func gotoLine(_ line: Int, column: Int = 0) {
        let clampedLine = max(0, min(line, max(0, lineCount - 1)))
        send(SCI_GOTOLINE, w: clampedLine)
        if column > 0 {
            let start = lineStart(clampedLine)
            let end = lineEnd(clampedLine)
            let target = min(start + column, end)
            send(SCI_GOTOPOS, w: target)
        }
    }

    func ensureVisible(line: Int) {
        send(SCI_ENSUREVISIBLEENFORCEPOLICY, w: line)
    }

    func scrollCaret() { send(SCI_SCROLLCARET) }

    func setAnchor(_ position: Int) {
        send(SCI_SETANCHOR, w: position)
    }

    // MARK: - Multiple selection / column editing

    func configureMultipleSelection() {
        send(SCI_SETMULTIPLESELECTION, w: 1)
        send(SCI_SETADDITIONALSELECTIONTYPING, w: 1)
        send(SCI_SETMULTIPASTE, w: Int(SC_MULTIPASTE_EACH))
        send(SCI_SETVIRTUALSPACEOPTIONS, w: Int(SCVS_RECTANGULARSELECTION | SCVS_USERACCESSIBLE))
        send(SCI_SETRECTANGULARSELECTIONMODIFIER, w: Int(SCMOD_ALT))
        send(SCI_SETADDITIONALCARETSVISIBLE, w: 1)
    }

    func addCaret(at position: Int) {
        send(SCI_ADDSELECTION, w: position, l: position)
    }

    func addCaretAbove() { addCaretVertically(direction: -1) }
    func addCaretBelow() { addCaretVertically(direction: 1) }

    private func addCaretVertically(direction: Int) {
        let caret = currentPosition
        let line = line(from: caret)
        let column = column(of: caret)
        let targetLine = line + direction
        guard targetLine >= 0, targetLine < lineCount else { return }
        let target = min(lineStart(targetLine) + column, lineEnd(targetLine))
        send(SCI_ADDSELECTION, w: target, l: target)
    }

    func selectNextOccurrence() {
        let selection = mainSelection
        let needle = selection.isEmpty ? wordAtCursor() : selectedText()
        guard !needle.isEmpty else { return }
        setSearchFlags(caseSensitive: true, wholeWord: false, regex: false)
        let from = selection.isEmpty ? currentPosition : selection.upperBound
        var found = searchInTarget(needle, from: from, to: length)
        if found == nil, from > 0 {
            found = searchInTarget(needle, from: 0, to: from)
        }
        if let found, found.length > 0 {
            send(SCI_ADDSELECTION, w: found.upperBound, l: found.location)
            send(SCI_SCROLLCARET)
        }
    }

    func selectAllOccurrences() {
        let selection = mainSelection
        guard !selection.isEmpty,
              let needle = Optional(text(inRange: NSRange(location: selection.lowerBound, length: selection.length))),
              !needle.isEmpty else { return }
        setSearchFlags(caseSensitive: true, wholeWord: false, regex: false)
        var selections: [EditorSelection] = []
        var position = 0
        while selections.count < 5000 {
            guard let found = searchInTarget(needle, from: position, to: length), found.length > 0 else { break }
            selections.append(EditorSelection(anchor: found.location, caret: found.upperBound))
            position = found.upperBound
        }
        if !selections.isEmpty {
            setSelections(selections)
        }
    }

    private func wordAtCursor() -> String {
        let caret = currentPosition
        var start = caret
        var end = caret
        let isWordByte: (Int) -> Bool = { position in
            guard position >= 0, position < self.length else { return false }
            let byte = self.character(at: position)
            return (byte >= 0x30 && byte <= 0x39)
                || (byte >= 0x41 && byte <= 0x5A)
                || (byte >= 0x61 && byte <= 0x7A)
                || byte == 0x5F
                || byte >= 0x80
        }
        while start > 0, isWordByte(start - 1) { start -= 1 }
        while end < length, isWordByte(end) { end += 1 }
        guard end > start else { return "" }
        return text(inRange: NSRange(location: start, length: end - start))
    }

    var isRectangleSelection: Bool {
        send(SCI_GETSELECTIONMODE) == Int(SC_SEL_RECTANGLE)
    }

    func setSelectionModeRectangle(_ rectangle: Bool) {
        if rectangle {
            send(SCI_SETSELECTIONMODE, w: Int(SC_SEL_RECTANGLE))
        } else {
            send(SCI_SETSELECTIONMODE, w: Int(SC_SEL_STREAM))
        }
    }

    // MARK: - EOL and encoding

    var eolMode: EOLMode {
        get {
            switch send(SCI_GETEOLMODE) {
            case Int(SC_EOL_CRLF): return .crlf
            case Int(SC_EOL_CR): return .cr
            default: return .lf
            }
        }
        set {
            switch newValue {
            case .crlf: send(SCI_SETEOLMODE, w: Int(SC_EOL_CRLF))
            case .cr: send(SCI_SETEOLMODE, w: Int(SC_EOL_CR))
            default: send(SCI_SETEOLMODE, w: Int(SC_EOL_LF))
            }
        }
    }

    func convertEOLs(to mode: EOLMode) {
        eolMode = mode
        send(SCI_CONVERTEOLS, w: send(SCI_GETEOLMODE))
    }

    func setCodePageUTF8() {
        send(SCI_SETCODEPAGE, w: Int(SC_CP_UTF8))
    }

    // MARK: - Margins

    func configureLineNumberMargin(width: Int) {
        send(SCI_SETMARGINTYPEN, w: 0, l: Int(SC_MARGIN_NUMBER))
        send(SCI_SETMARGINWIDTHN, w: 0, l: width)
        send(SCI_SETMARGINLEFT, w: 0, l: 0)
    }

    func configureBookmarkMargin() {
        send(SCI_SETMARGINTYPEN, w: 1, l: Int(SC_MARGIN_SYMBOL))
        send(SCI_SETMARGINMASKN, w: 1, l: 1 << PXMarker.bookmark)
        send(SCI_SETMARGINWIDTHN, w: 1, l: 14)
        send(SCI_SETMARGINSENSITIVEN, w: 1, l: 1)
        send(SCI_MARKERSETBACK, w: Int(PXMarker.bookmark), l: Int(0x1E7AF0))
    }

    func configureFoldMargin() {
        send(SCI_SETMARGINTYPEN, w: 2, l: Int(SC_MARGIN_SYMBOL))
        send(SCI_SETMARGINMASKN, w: 2, l: Int(SC_MASK_FOLDERS))
        send(SCI_SETMARGINWIDTHN, w: 2, l: 14)
        send(SCI_SETMARGINSENSITIVEN, w: 2, l: 1)
        send(SCI_SETPROPERTY, key: "fold", value: "1")
        send(SCI_SETPROPERTY, key: "fold.comment", value: "1")
    }

    func updateLineNumberMarginWidth(fontName: String, fontSize: CGFloat) {
        let digits = max(3, String(max(1, lineCount)).count)
        var sample = ""
        sample.reserveCapacity(digits)
        for _ in 0..<digits { sample.append("9") }
        let width = send(SCI_TEXTWIDTH, w: Int(STYLE_LINENUMBER), string: sample) + 12
        send(SCI_SETMARGINWIDTHN, w: 0, l: width)
        _ = fontName
        _ = fontSize
    }

    func setMarginWidth(_ margin: Int, width: Int) {
        send(SCI_SETMARGINWIDTHN, w: margin, l: width)
    }

    // MARK: - Markers (bookmarks)

    enum PXMarker {
        static let bookmark: Int32 = 24
    }

    func defineStandardMarkers() {
        send(SCI_MARKERDEFINE, w: Int(PXMarker.bookmark), l: Int(SC_MARK_BOOKMARK))
        send(SCI_MARKERSETFORE, w: Int(PXMarker.bookmark), l: Int(0xFFFFFF))
    }

    func addMarker(_ marker: Int, line: Int) {
        send(SCI_MARKERADD, w: line, l: marker)
    }

    func removeMarker(_ marker: Int, line: Int) {
        send(SCI_MARKERDELETE, w: line, l: marker)
    }

    func clearMarkers(_ marker: Int) {
        send(SCI_MARKERDELETEALL, w: marker)
    }

    func hasMarker(_ marker: Int, line: Int) -> Bool {
        send(SCI_MARKERGET, w: line) & (1 << marker) != 0
    }

    func nextMarkerLine(_ marker: Int, from line: Int, wrap: Bool = true) -> Int? {
        var result = send(SCI_MARKERNEXT, w: line + 1, l: 1 << marker)
        if result < 0 && wrap {
            result = send(SCI_MARKERNEXT, w: 0, l: 1 << marker)
        }
        return result >= 0 ? result : nil
    }

    func previousMarkerLine(_ marker: Int, from line: Int, wrap: Bool = true) -> Int? {
        var result = send(SCI_MARKERPREVIOUS, w: line - 1, l: 1 << marker)
        if result < 0 && wrap {
            result = send(SCI_MARKERPREVIOUS, w: max(0, lineCount - 1), l: 1 << marker)
        }
        return result >= 0 ? result : nil
    }

    // MARK: - Folding

    func setFoldingEnabled(_ enabled: Bool) {
        send(SCI_SETFOLDFLAGS, w: enabled ? Int(SC_FOLDFLAG_LINEAFTER_CONTRACTED) : 0)
        send(SCI_SETAUTOMATICFOLD, w: enabled
            ? Int(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CHANGE | SC_AUTOMATICFOLD_CLICK)
            : 0)
    }

    func foldAction(_ action: ScintillaFoldAction, line: Int) {
        switch action {
        case .toggle: send(SCI_TOGGLEFOLD, w: line)
        case .contract: send(SCI_FOLDLINE, w: line, l: Int(SC_FOLDACTION_CONTRACT))
        case .expand: send(SCI_FOLDLINE, w: line, l: Int(SC_FOLDACTION_EXPAND))
        case .contractAll: send(SCI_FOLDALL, w: Int(SC_FOLDACTION_CONTRACT))
        case .expandAll: send(SCI_FOLDALL, w: Int(SC_FOLDACTION_EXPAND))
        }
    }

    func isFoldHeader(_ line: Int) -> Bool {
        send(SCI_GETFOLDLEVEL, w: line) & Int(SC_FOLDLEVELHEADERFLAG) != 0
    }

    func foldLevel(of line: Int) -> Int {
        send(SCI_GETFOLDLEVEL, w: line) & Int(SC_FOLDLEVELNUMBERMASK)
    }

    func setFoldLevel(_ line: Int, level: Int) {
        send(SCI_SETFOLDLEVEL, w: line, l: level)
    }

    // MARK: - Indicators

    enum Indicator: Int32 {
        case searchMatch = 0
        case currentMatch = 1
        case diffAdded = 2
        case diffRemoved = 3
        case diffChanged = 4

        var style: Int32 {
            switch self {
            case .searchMatch, .currentMatch: return Int32(INDIC_STRAIGHTBOX)
            case .diffAdded, .diffRemoved, .diffChanged: return Int32(INDIC_FULLBOX)
            }
        }
    }

    func configureIndicator(_ indicator: Indicator, color: NSColor, alpha: Int, outlineAlpha: Int = 255, under: Bool = false) {
        send(SCI_INDICSETSTYLE, w: Int(indicator.rawValue), l: Int(indicator.style))
        send(SCI_INDICSETFORE, w: Int(indicator.rawValue), l: Int(pxColorInt(color)))
        send(SCI_INDICSETALPHA, w: Int(indicator.rawValue), l: alpha)
        send(SCI_INDICSETOUTLINEALPHA, w: Int(indicator.rawValue), l: outlineAlpha)
        send(SCI_INDICSETUNDER, w: Int(indicator.rawValue), l: under ? 1 : 0)
    }

    func addIndicator(_ indicator: Indicator, range: NSRange) {
        guard range.length > 0 else { return }
        send(SCI_SETINDICATORCURRENT, w: Int(indicator.rawValue))
        send(SCI_INDICATORFILLRANGE, w: range.location, l: range.length)
    }

    func clearIndicators(_ indicator: Indicator) {
        send(SCI_SETINDICATORCURRENT, w: Int(indicator.rawValue))
        send(SCI_INDICATORCLEARRANGE, w: 0, l: length)
    }

    func clearAllIndicators() {
        send(SCI_INDICATORCLEARRANGE, w: 0, l: length)
    }

    // MARK: - Search support (target based)

    func setSearchFlags(caseSensitive: Bool, wholeWord: Bool, regex: Bool) {
        var flags = 0
        if caseSensitive { flags |= Int(SCFIND_MATCHCASE) }
        if wholeWord { flags |= Int(SCFIND_WHOLEWORD) }
        if regex {
            flags |= Int(SCFIND_REGEXP)
            // Use the ECMAScript-compatible engine so patterns like
            // "([a-z]+) (\\d+)" and "\\1" backreferences behave as users
            // expect from Notepad++-style editing.
            flags |= Int(SCFIND_CXX11REGEX)
        }
        send(SCI_SETSEARCHFLAGS, w: flags)
    }

    func searchInTarget(_ needle: String, from: Int, to: Int) -> NSRange? {
        send(SCI_SETTARGETSTART, w: from)
        send(SCI_SETTARGETEND, w: to)
        let found = send(SCI_SEARCHINTARGET, w: needle.utf8.count, string: needle)
        guard found >= 0 else { return nil }
        let start = send(SCI_GETTARGETSTART)
        let end = send(SCI_GETTARGETEND)
        return NSRange(location: start, length: end - start)
    }

    func replaceTarget(with replacement: String, regex: Bool) {
        send(regex ? SCI_REPLACETARGETRE : SCI_REPLACETARGET, w: replacement.utf8.count, string: replacement)
    }

    var targetStart: Int { send(SCI_GETTARGETSTART) }
    var targetEnd: Int { send(SCI_GETTARGETEND) }

    func setTarget(start: Int, end: Int) {
        send(SCI_SETTARGETSTART, w: start)
        send(SCI_SETTARGETEND, w: end)
    }

    // MARK: - Lexing

    func setLanguage(_ language: LanguageDefinition, keywordsOnly: Bool = false) {
        if let lexerName = language.lexerName {
            if lexerName == "swift" {
                PXSciBridge.applySwiftLexer(to: view,
                                            keywords: language.keywordString,
                                            types: language.typeString,
                                            builtins: language.builtinString)
            } else if let lexer = PXSciBridge.createLexerNamed(lexerName) {
                PXSciBridge.applyLexer(lexer, to: view)
                if !language.keywords.isEmpty || !language.types.isEmpty || !language.builtins.isEmpty {
                    _ = send(SCI_SETKEYWORDS, w: 0, string: language.keywordString)
                    _ = send(SCI_SETKEYWORDS, w: 1, string: language.typeString)
                    _ = send(SCI_SETKEYWORDS, w: 2, string: language.builtinString)
                }
            }
            if language.id == "html" || language.id == "php" {
                send(SCI_SETPROPERTY, key: "asp.default.language", value: "1")
                send(SCI_SETPROPERTY, key: "xml.allow.script", value: "1")
            }
        } else {
            PXSciBridge.applyLexer(nil, to: view)
        }
        _ = keywordsOnly
        send(SCI_COLOURISE, w: 0, l: -1)
        if language.supportsFolding {
            setFoldingEnabled(true)
            send(SCI_SETMARGINWIDTHN, w: 2, l: 14)
        } else {
            setFoldingEnabled(false)
            send(SCI_SETMARGINWIDTHN, w: 2, l: 0)
        }
    }

    func colourise(from: Int, to: Int) {
        send(SCI_COLOURISE, w: from, l: to)
    }

    /// Language identifier reported by the installed lexer (0 = container/none).
    var lexerIdentifier: Int {
        send(SCI_GETLEXER)
    }

    // MARK: - Styles and theme application

    func applyFont(name: String, size: CGFloat) {
        send(SCI_STYLESETFONT, w: Int(STYLE_DEFAULT), string: name)
        send(SCI_STYLESETSIZE, w: Int(STYLE_DEFAULT), l: Int(size))
        send(SCI_STYLECLEARALL)
    }

    func applyTheme(_ theme: EditorTheme, fontName: String, fontSize: CGFloat, language: LanguageDefinition) {
        send(SCI_STYLESETFORE, w: Int(STYLE_DEFAULT), l: Int(pxColorInt(theme.foreground)))
        send(SCI_STYLESETBACK, w: Int(STYLE_DEFAULT), l: Int(pxColorInt(theme.background)))
        send(SCI_STYLESETFONT, w: Int(STYLE_DEFAULT), string: fontName)
        send(SCI_STYLESETSIZE, w: Int(STYLE_DEFAULT), l: Int(fontSize))
        send(SCI_STYLECLEARALL)

        // Apply every style referenced by the language map.
        let defaultAttributes = theme.attributes(for: .text)
        let mappedStyleIDs = Set(language.styleMap.keys).union([0])
        for styleID in mappedStyleIDs {
            let semantic = language.styleMap[styleID] ?? .text
            let attributes = theme.attributes(for: semantic)
            applyStyleAttributes(attributes, styleID: styleID)
            _ = defaultAttributes
        }

        // All remaining lexer styles (styles not in the map) get plain text look.
        for styleID in 0..<256 {
            if mappedStyleIDs.contains(styleID) { continue }
            if styleID == Int(STYLE_DEFAULT) || styleID == Int(STYLE_LINENUMBER) { continue }
            guard styleID < Int(STYLE_MAX) else { break }
            applyStyleAttributes(defaultAttributes, styleID: styleID)
        }

        // Chrome styles
        applyStyleAttributes(StyleAttributes(foreground: theme.foreground, background: theme.background), styleID: Int(STYLE_DEFAULT))
        applyStyleAttributes(StyleAttributes(foreground: theme.lineNumberForeground, background: theme.lineNumberBackground), styleID: Int(STYLE_LINENUMBER))
        applyStyleAttributes(StyleAttributes(foreground: theme.indentGuide), styleID: Int(STYLE_INDENTGUIDE))
        applyStyleAttributes(StyleAttributes(foreground: theme.caret, background: theme.searchCurrentFill), styleID: Int(STYLE_BRACELIGHT))
        applyStyleAttributes(StyleAttributes(foreground: NSColor.systemRed), styleID: Int(STYLE_BRACEBAD))
        applyStyleAttributes(StyleAttributes(foreground: theme.foreground, background: theme.background), styleID: Int(STYLE_CONTROLCHAR))
        applyStyleAttributes(StyleAttributes(foreground: theme.foreground, background: theme.lineNumberBackground), styleID: Int(STYLE_CALLTIP))

        // Whitespace / EOL markers
        send(SCI_SETWHITESPACEFORE, w: 1, l: Int(pxColorInt(theme.whitespaceForeground)))
        send(SCI_SETWHITESPACEBACK, w: 0, l: Int(pxColorInt(theme.background)))
        send(SCI_SETWHITESPACESIZE, w: 1)

        // Caret line
        send(SCI_SETCARETLINEVISIBLE, w: 1)
        send(SCI_SETCARETLINEBACK, w: Int(pxColorInt(theme.caretLineBackground)))

        // Selection colours
        send(SCI_SETSELBACK, w: 1, l: Int(pxColorInt(theme.selectionBackground)))
        send(SCI_SETADDITIONALSELBACK, w: 1, l: Int(pxColorInt(theme.selectionBackground)))
        if let selectionForeground = theme.selectionForeground {
            send(SCI_SETSELFORE, w: 1, l: Int(pxColorInt(selectionForeground)))
        } else {
            send(SCI_SETSELFORE, w: 0, l: 0)
        }
        send(SCI_SETSELALPHA, w: 255)

        // Fold margin
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDER), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDER), l: Int(pxColorInt(theme.foldMarkerForeground)))
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDEROPEN), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDEROPEN), l: Int(pxColorInt(theme.foldMarkerForeground)))
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDERSUB), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDERSUB), l: Int(pxColorInt(theme.foldMarkerForeground)))
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDERTAIL), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDERTAIL), l: Int(pxColorInt(theme.foldMarkerForeground)))
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDERMIDTAIL), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDERMIDTAIL), l: Int(pxColorInt(theme.foldMarkerForeground)))
        send(SCI_MARKERSETBACK, w: Int(SC_MARKNUM_FOLDEREND), l: Int(pxColorInt(theme.lineNumberBackground)))
        send(SCI_MARKERSETFORE, w: Int(SC_MARKNUM_FOLDEREND), l: Int(pxColorInt(theme.foldMarkerForeground)))

        // Indicators
        configureIndicator(.searchMatch, color: theme.searchMatchOutline, alpha: 90, outlineAlpha: 160)
        configureIndicator(.currentMatch, color: theme.searchCurrentFill, alpha: 160, outlineAlpha: 220)
        configureIndicator(.diffAdded, color: NSColor(pxHex: 0x2FA84F), alpha: 60, outlineAlpha: 90)
        configureIndicator(.diffRemoved, color: NSColor(pxHex: 0xE5484D), alpha: 60, outlineAlpha: 90)
        configureIndicator(.diffChanged, color: NSColor(pxHex: 0xE5B800), alpha: 60, outlineAlpha: 90)

        // Bookmark margin colors
        send(SCI_MARKERSETBACK, w: Int(PXMarker.bookmark), l: Int(pxColorInt(theme.bookmarkColor)))
    }

    private func applyStyleAttributes(_ attributes: StyleAttributes, styleID: Int) {
        send(SCI_STYLESETFORE, w: styleID, l: Int(pxColorInt(attributes.foreground)))
        if let background = attributes.background {
            send(SCI_STYLESETBACK, w: styleID, l: Int(pxColorInt(background)))
        }
        send(SCI_STYLESETBOLD, w: styleID, l: attributes.bold ? 1 : 0)
        send(SCI_STYLESETITALIC, w: styleID, l: attributes.italic ? 1 : 0)
        send(SCI_STYLESETUNDERLINE, w: styleID, l: attributes.underline ? 1 : 0)
    }

    func setIndentationGuides(_ visible: Bool) {
        send(SCI_SETINDENTATIONGUIDES, w: visible ? Int(SC_IV_LOOKBOTH) : Int(SC_IV_NONE))
    }

    func setWhitespaceVisible(_ visible: Bool) {
        send(SCI_SETVIEWWS, w: visible ? Int(SCWS_VISIBLEALWAYS) : Int(SCWS_INVISIBLE))
    }

    func setEOLVisible(_ visible: Bool) {
        send(SCI_SETVIEWEOL, w: visible ? 1 : 0)
    }

    func setWrapMode(_ enabled: Bool) {
        send(SCI_SETWRAPMODE, w: enabled ? Int(SC_WRAP_WORD) : Int(SC_WRAP_NONE))
    }

    var wrapModeEnabled: Bool { send(SCI_GETWRAPMODE) != Int(SC_WRAP_NONE) }

    func setTabWidth(_ width: Int) {
        send(SCI_SETTABWIDTH, w: max(1, min(width, 32)))
    }

    func setUseTabs(_ useTabs: Bool) {
        send(SCI_SETUSETABS, w: useTabs ? 1 : 0)
    }

    var zoom: Int {
        get { send(SCI_GETZOOM) }
        set { send(SCI_SETZOOM, w: max(-10, min(newValue, 20))) }
    }

    func setBaseFontSize(_ size: CGFloat) {
        send(SCI_STYLESETSIZE, w: Int(STYLE_DEFAULT), l: Int(size))
        send(SCI_STYLECLEARALL)
    }

    // MARK: - Indentation operations

    func indentSelection(by levels: Int) {
        beginUndoAction()
        defer { endUndoAction() }
        for selection in allSelections() {
            let firstLine = line(from: selection.lowerBound)
            let lastLine = line(from: selection.upperBound)
            for line in firstLine...max(firstLine, lastLine) {
                updateLineIndentation(line, delta: levels)
            }
        }
    }

    private func updateLineIndentation(_ line: Int, delta: Int) {
        let current = send(SCI_GETLINEINDENTATION, w: line)
        let tabWidth = send(SCI_GETTABWIDTH)
        let step = max(1, tabWidth)
        let newValue = max(0, current + delta * step)
        send(SCI_SETLINEINDENTATION, w: line, l: newValue)
    }

    // MARK: - Scroll state

    var firstVisibleLine: Int { send(SCI_GETFIRSTVISIBLELINE) }
    var xOffset: Int { send(SCI_GETXOFFSET) }

    func setScrollState(firstVisibleLine: Int, xOffset: Int) {
        send(SCI_SETFIRSTVISIBLELINE, w: firstVisibleLine)
        send(SCI_SETXOFFSET, w: xOffset)
        send(SCI_CHOOSECARETX)
    }

    func scrollToLine(_ line: Int) {
        send(SCI_ENSUREVISIBLE, w: line)
        send(SCI_SCROLLCARET)
    }

    // MARK: - Notification bridge

    func notification(_ notification: UnsafeMutablePointer<SCNotification>!) {
        let info = notification.pointee
        switch Int(info.nmhdr.code) {
        case Int(SCN_UPDATEUI):
            delegate?.scintillaDidUpdateUI(self)
        case Int(SCN_SAVEPOINTREACHED):
            delegate?.scintillaDidChangeDirtyState(self, isDirty: false)
        case Int(SCN_SAVEPOINTLEFT):
            delegate?.scintillaDidChangeDirtyState(self, isDirty: true)
        case Int(SCN_CHARADDED):
            delegate?.scintillaDidTypeCharacter(self, byte: UInt8(truncatingIfNeeded: info.ch))
        case Int(SCN_MODIFIED):
            var insertedText: String?
            if info.modificationType & Int32(SC_MOD_INSERTTEXT) != 0, info.length > 0, let pointer = info.text {
                insertedText = String(cString: pointer)
            }
            let modification = ScintillaModification(
                position: info.position,
                length: info.length,
                linesAdded: info.linesAdded,
                modificationType: Int(info.modificationType),
                insertedText: insertedText
            )
            delegate?.scintillaDidChangeContent(self, modification: modification)
        case Int(SCN_MARGINCLICK):
            let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(info.modifiers))
            delegate?.scintillaMarginClicked(self, margin: Int(info.margin),
                                             modifiers: modifierFlags, position: info.position)
        default:
            break
        }
    }
}

// MARK: - Color helper

func pxColorInt(_ color: NSColor) -> Int {
    guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
    let red = Int(round(rgb.redComponent * 255))
    let green = Int(round(rgb.greenComponent * 255))
    let blue = Int(round(rgb.blueComponent * 255))
    return (blue << 16) | (green << 8) | red
}
