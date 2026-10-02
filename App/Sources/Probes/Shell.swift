import Foundation

/// Runs a fixed system binary with fixed arguments and returns its output.
/// Never goes through a shell, so no argument is ever interpreted.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var output: String
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 30) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            let box = OutputBox()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { box.append(data) }
            }
            process.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                box.append(pipe.fileHandleForReading.readDataToEndOfFile())
                continuation.resume(returning: Result(status: p.terminationStatus, output: box.string))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: Result(status: -1, output: ""))
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}

/// Thread-safe byte accumulator for a process's output.
final class OutputBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var string: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
