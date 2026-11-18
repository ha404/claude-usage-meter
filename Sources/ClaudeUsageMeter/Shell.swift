import Foundation

/// Runs command-line tools without blocking Swift's cooperative thread pool: a tool that
/// waits on the user (a Keychain prompt, say) parks a GCD thread instead.
enum Shell {
    struct Result {
        let status: Int32
        let output: Data

        var text: String {
            String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func run(_ executable: String, _ arguments: [String]) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Swift.Result { try runBlocking(executable, arguments) })
            }
        }
    }

    private static func runBlocking(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain the pipe before waiting, or a chatty tool deadlocks on a full buffer.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: output)
    }
}
