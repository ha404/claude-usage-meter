import Foundation
import Testing
@testable import ClaudeUsageMeter

/// The status line re-implements the app's pace logic in bash. These run the real script
/// so the two can't drift apart.
private let script = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("scripts/statusline.sh")

/// Runs the script on `input`. `cache` is the app's cache file as the script would find it.
private func statusLine(_ input: String, cache: String? = nil) throws -> String {
    let home = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    if let cache {
        let dir = home.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(cache.utf8).write(to: dir.appendingPathComponent("usage-meter-cache.json"))
    }
    let process = Process()
    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [script.path]
    // A private HOME keeps the app's real cache file out of the test.
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
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

// MARK: - Choosing between Claude Code's numbers and the app's cache

private let epoch = Int(Date().timeIntervalSince1970)

private func session(used: Double, resetsIn: Int) -> String {
    "{\"rate_limits\":{\"five_hour\":{\"used_percentage\":\(used),\"resets_at\":\(epoch + resetsIn)}}}"
}

private func cache(used: Double, resetsIn: Int, age: Int = 5) -> String {
    "{\"timestamp\":\(epoch - age),\"five_hour\":{\"utilization\":\(used),\"resets_at\":\(epoch + resetsIn)}}"
}

@Test func statusLinePrefersFresherCacheOverIdleSession() throws {
    // The session last heard 20%; the app has since measured 55% in the same window.
    let line = try statusLine(session(used: 20, resetsIn: 9000), cache: cache(used: 55, resetsIn: 9002))
    #expect(line.contains("55%"))
}

@Test func statusLineKeepsSessionWhenCacheLags() throws {
    // A response just landed (60%) and the app hasn't polled since (40%).
    let line = try statusLine(session(used: 60, resetsIn: 9000), cache: cache(used: 40, resetsIn: 9000))
    #expect(line.contains("60%"))
}

@Test func statusLinePrefersTheNewerWindow() throws {
    // Lower usage, but from a window that resets later: the old one has rolled over.
    let line = try statusLine(session(used: 90, resetsIn: 300), cache: cache(used: 3, resetsIn: 17000))
    #expect(line.contains(" 3%"))
}

@Test func statusLineIgnoresAnOldCache() throws {
    let line = try statusLine(session(used: 20, resetsIn: 9000), cache: cache(used: 55, resetsIn: 9000, age: 700))
    #expect(line.contains("20%"))
}

@Test func statusLineFallsBackToCacheWithoutSessionLimits() throws {
    #expect(try statusLine("{}", cache: cache(used: 55, resetsIn: 9000)).contains("55%"))
}

// MARK: - Installing and removing

private let installer = script.deletingLastPathComponent().appendingPathComponent("install-statusline.sh")

/// Runs the installer against a private HOME and returns the resulting settings.json.
private func runInstaller(_ arguments: [String] = [], home: URL) throws -> [String: Any] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [installer.path] + arguments
    process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let settings = try Data(contentsOf: home.appendingPathComponent(".claude/settings.json"))
    return try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
}

private func temporaryHome(settings: String) throws -> URL {
    let home = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString)
    let dir = home.appendingPathComponent(".claude")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(settings.utf8).write(to: dir.appendingPathComponent("settings.json"))
    return home
}

@Test func installerAddsAndRemovesTheStatusLine() throws {
    let home = try temporaryHome(settings: #"{"theme":"dark"}"#)
    defer { try? FileManager.default.removeItem(at: home) }
    let installed = home.appendingPathComponent(".claude/usage-meter-statusline.sh")

    let entry = try #require(try runInstaller(home: home)["statusLine"] as? [String: Any])
    #expect((entry["command"] as? String)?.contains("usage-meter-statusline.sh") == true)
    #expect(entry["refreshInterval"] as? Int == 10)
    #expect(FileManager.default.fileExists(atPath: installed.path))

    let after = try runInstaller(["--uninstall"], home: home)
    #expect(after["statusLine"] == nil)
    #expect(after["theme"] as? String == "dark")
    #expect(!FileManager.default.fileExists(atPath: installed.path))
}

@Test func uninstallLeavesAnotherToolsStatusLineAlone() throws {
    let home = try temporaryHome(settings: #"{"statusLine":{"type":"command","command":"my-line.sh"}}"#)
    defer { try? FileManager.default.removeItem(at: home) }
    let entry = try runInstaller(["--uninstall"], home: home)["statusLine"] as? [String: Any]
    #expect(entry?["command"] as? String == "my-line.sh")
}
