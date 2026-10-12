//
//  MacroEngine.swift
//  PlainX Editor
//
//  Records semantic editor operations (typed text + registered command
//  invocations) and replays them deterministically. Raw mouse geometry is
//  never recorded.
//

import AppKit

struct MacroStep: Codable, Equatable {
    enum Kind: String, Codable {
        case insertText
        case deleteBackwards
        case command
    }

    var kind: Kind
    var text: String?
    var commandID: String?

    static func insert(_ text: String) -> MacroStep {
        MacroStep(kind: .insertText, text: text, commandID: nil)
    }

    static func deleteBackwards(_ count: Int = 1) -> MacroStep {
        MacroStep(kind: .deleteBackwards, text: String(repeating: "\u{8}", count: count), commandID: nil)
    }

    static func command(_ id: String) -> MacroStep {
        MacroStep(kind: .command, text: nil, commandID: id)
    }
}

struct Macro: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var steps: [MacroStep]
    var createdAt: Date = Date()

    var stepCount: Int { steps.count }
}

final class MacroStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("PlainX", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.fileURL = directory.appendingPathComponent("Macros.json")
        }
    }

    func load() -> [Macro] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Macro].self, from: data)) ?? []
    }

    func save(_ macros: [Macro]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(macros)
        try data.write(to: fileURL, options: [.atomic])
    }
}

final class MacroEngine {
    private(set) var isRecording = false
    var lastMacro: Macro?
    private var buffer: String = ""
    private var steps: [MacroStep] = []
    private(set) var macros: [Macro]
    private let store: MacroStore

    static let maxPlaybackIterations = 200
    static let maxRecordedSteps = 20_000

    init(store: MacroStore = MacroStore()) {
        self.store = store
        self.macros = store.load()
    }

    var typedText: String { buffer }

    func startRecording() {
        steps = []
        buffer = ""
        isRecording = true
    }

    @discardableResult
    func stopRecording(name: String) -> Macro {
        flushBuffer()
        isRecording = false
        let macro = Macro(name: name, steps: steps)
        lastMacro = macro
        steps = []
        return macro
    }

    func cancelRecording() {
        isRecording = false
        steps = []
        buffer = ""
    }

    func recordTypedByte(_ byte: UInt8, tab: DocumentTabController?) {
        guard isRecording else { return }
        appendByte(byte)
        if steps.count >= Self.maxRecordedSteps {
            // Safety cap: stop recording rather than growing without bound.
            _ = stopRecording(name: "Recorded Macro")
        }
    }

    /// Typed bytes may be split across UTF-8 sequences, so bytes are buffered
    /// and flushed as one insertText step on any other event.
    func appendByte(_ byte: UInt8) {
        if byte == 0x08 {
            buffer.append("\u{8}")
        } else if let scalar = String(bytes: [byte], encoding: .utf8) {
            buffer.append(scalar)
        } else {
            // Continuation byte; append via raw accumulation.
            var bytes = Array(buffer.utf8)
            bytes.append(byte)
            buffer = String(decoding: bytes, as: UTF8.self)
        }
    }

    func recordCommand(_ commandID: String) {
        guard isRecording else { return }
        flushBuffer()
        steps.append(.command(commandID))
        enforceRecordingCap()
    }

    private func enforceRecordingCap() {
        if steps.count >= Self.maxRecordedSteps {
            _ = stopRecording(name: "Recorded Macro")
        }
    }

    func flushBuffer() {
        guard !buffer.isEmpty else { return }
        // Decode backspace runs into delete steps.
        var currentInsert = ""
        for scalar in buffer {
            if scalar == "\u{8}" {
                if !currentInsert.isEmpty {
                    steps.append(.insert(currentInsert))
                    currentInsert = ""
                }
                steps.append(.deleteBackwards())
            } else {
                currentInsert.append(scalar)
            }
        }
        if !currentInsert.isEmpty {
            steps.append(.insert(currentInsert))
        }
        buffer = ""
    }

    // MARK: - Playback

    func play(_ macro: Macro, times: Int, tab: DocumentTabController, coordinator: AppCoordinator) {
        let iterations = max(1, min(times, Self.maxPlaybackIterations))
        for _ in 0..<iterations {
            for step in macro.steps {
                switch step.kind {
                case .insertText:
                    if let text = step.text {
                        tab.performSyncedEdit { $0.facade.insert(text: text, at: $0.facade.currentPosition) }
                    }
                case .deleteBackwards:
                    let count = step.text?.count ?? 1
                    tab.performSyncedEdit { pane in
                        for _ in 0..<count {
                            let position = pane.facade.currentPosition
                            guard position > 0 else { break }
                            pane.facade.deleteRange(location: position - 1, length: 1)
                        }
                    }
                case .command:
                    if let commandID = step.commandID {
                        let window = tab.controller
                        let context = CommandContext(coordinator: coordinator, window: window)
                        CommandRegistry.shared.perform(commandID, context: context)
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    func add(_ macro: Macro) {
        macros.append(macro)
        try? store.save(macros)
    }

    func remove(_ macro: Macro) {
        macros.removeAll { $0.id == macro.id }
        try? store.save(macros)
    }

    func rename(_ macro: Macro, to name: String) {
        guard let index = macros.firstIndex(where: { $0.id == macro.id }) else { return }
        macros[index].name = name
        try? store.save(macros)
    }
}
