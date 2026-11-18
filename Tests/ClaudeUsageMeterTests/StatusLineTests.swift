import Foundation
import Testing
@testable import ClaudeUsageMeter

/// The status line re-implements the app's pace logic in bash. These run the real script
/// so the two can't drift apart.
private let script = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("scripts/statusline.sh")

private func statusLine(_ input: String) throws -> String {
    let process = Process()
    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path]
    // An empty HOME keeps the app's real cache file out of the test.
    process.environment = ["HOME": NSTemporaryDirectory() + UUID().uuidString, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let out = stdout.fileHandleForReading.readDataToEndOfFile()
    let err = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(err.isEmpty, "status line wrote to stderr: \(String(decoding: err, as: UTF8.self))")
    return String(decoding: out, as: UTF8.self)
}

private func input(used: Double, elapsed: Double?) -> String {
    let resets = elapsed.map { ",\"resets_at\":\(Int(Date().timeIntervalSince1970 + 18000 * (1 - $0)))" } ?? ""
    return "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(used)\(resets)}}}"
}

/// The severity the script chose, read back from the colour it drew the bar in.
private func severity(in line: String) -> Severity? {
    if line.contains("LIMIT") { return .exhausted }
    guard let label = line.range(of: "5h\u{1B}[0m \u{1B}[") else { return nil }
    return ["32": Severity.normal, "33": .warning, "31": .critical][String(line[label.upperBound...].prefix(2))]
}

@Test(arguments: paceCases.indices)
func statusLineAgreesWithApp(_ index: Int) throws {
    let c = paceCases[index]
    #expect(severity(in: try statusLine(input(used: c.used, elapsed: c.elapsed))) == c.expected)
}

@Test func statusLineFillPassesMarkerOnlyWhenAheadOfPace() throws {
    // 41% used, 44% elapsed: behind pace, so no filled cell may sit right of the marker.
    let behind = try statusLine(input(used: 41, elapsed: 0.44))
    #expect(behind.split(separator: "│").dropFirst().first?.contains("▓") == false)
    // 48% used, 30% elapsed: ahead, so the cell right after the marker is filled.
    let ahead = try statusLine(input(used: 48, elapsed: 0.30))
    #expect(ahead.contains("│\u{1B}[0m\u{1B}[33m▓"))
}

@Test func statusLineDropsMalformedWindows() throws {
    #expect(try statusLine(#"{"rate_limits":{"five_hour":{"resets_at":1800000000}}}"#) == "\n")
    #expect(try statusLine(#"{"rate_limits":{"five_hour":{"used_percentage":"40"}}}"#) == "\n")
    #expect(try statusLine(#"{"rate_limits":"nope"}"#) == "\n")
    #expect(try statusLine("") == "\n")
}

@Test func statusLineToleratesFractionalResetTime() throws {
    let resets = Date().timeIntervalSince1970 + 9000.5
    let line = try statusLine("{\"rate_limits\":{\"five_hour\":{\"used_percentage\":40,\"resets_at\":\(resets)}}}")
    #expect(line.contains("40%"))
}

@Test func statusLineRoundsPercentLikeTheApp() throws {
    #expect(try statusLine(input(used: 48.6, elapsed: nil)).contains("49%"))
}
