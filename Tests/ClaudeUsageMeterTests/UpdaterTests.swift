import Foundation
import Testing
@testable import ClaudeUsageMeter

@Test func parsesVersions() {
    #expect(AppVersion("v1.0.12")?.parts == [1, 0, 12])
    #expect(AppVersion("1.2")?.description == "1.2")
    #expect(AppVersion("") == nil)
    #expect(AppVersion("1..2") == nil)
    #expect(AppVersion("1.0-beta") == nil)
    #expect(AppVersion("latest") == nil)
}

@Test func comparesVersionsNumerically() throws {
    let v = { (s: String) in try #require(AppVersion(s)) }
    #expect(try v("1.0.9") < v("1.0.10"))
    #expect(try v("1.0.10") < v("1.1"))
    #expect(try v("1.0") == v("v1.0.0"))
    #expect(try !(v("1.0") < v("1.0.0")))
    #expect(try v("2") > v("1.99.99"))
}

@Test func decodesRelease() throws {
    let json = """
    {"tag_name":"v1.0.9","assets":[
      {"name":"notes.txt","url":"https://api.github.com/repos/o/r/releases/assets/1"},
      {"name":"ClaudeUsageMeter.zip","url":"https://api.github.com/repos/o/r/releases/assets/2","digest":"sha256:abc"}]}
    """
    let release = try JSONDecoder().decode(Release.self, from: Data(json.utf8))
    #expect(release.version == AppVersion("1.0.9"))
    #expect(release.archive?.url.lastPathComponent == "2")
    #expect(release.archive?.digest == "sha256:abc")
}

@Test func sha256MatchesGitHubDigestFormat() {
    #expect(Updater.sha256(Data("abc".utf8)) == "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}
