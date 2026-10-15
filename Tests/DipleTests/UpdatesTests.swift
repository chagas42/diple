import Testing
import Foundation
import CryptoKit
@testable import Diple

struct UpdatesTests {
    @Test func aHigherPartIsNewer() {
        #expect(Updates.isNewer("1.14.0", than: "1.13.3"))
        #expect(Updates.isNewer("2.0.0", than: "1.99.99"))
        #expect(Updates.isNewer("1.13.10", than: "1.13.9"))
    }

    @Test func theSameOrOlderIsNot() {
        #expect(!Updates.isNewer("1.13.3", than: "1.13.3"))
        #expect(!Updates.isNewer("1.13.2", than: "1.13.3"))
    }

    @Test func aMissingPartCountsAsZero() {
        #expect(!Updates.isNewer("1.13", than: "1.13.0"))
        #expect(Updates.isNewer("1.13.1", than: "1.13"))
    }
}

@MainActor
struct ReleaseNotesTests {
    struct Latest: Transport {
        let tag: String
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let body = #"{"tag_name":"\#(tag)","html_url":"https://github.com/chagas42/diple/releases/tag/\#(tag)"}"#
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        }
    }

    @Test func withNothingNewerTheyAreThisVersionsNotes() async {
        let updates = Updates()
        updates.transport = Latest(tag: "v\(updates.installed)")
        await updates.check()
        #expect(updates.state == .current)
        #expect(updates.releaseNotes.absoluteString == "https://github.com/chagas42/diple/releases/tag/v\(updates.installed)")
    }

    @Test func withANewerReleaseTheyAreThatReleasesNotes() async {
        let updates = Updates()
        updates.transport = Latest(tag: "v999.0.0")
        await updates.check()
        #expect(updates.releaseNotes.absoluteString == "https://github.com/chagas42/diple/releases/tag/v999.0.0")
    }

    @Test func aBuildOutsideApplicationsDoesNotInstallItself() {
        #expect(!Updates().canInstall)
    }

    static let page = URL(string: "https://github.com/chagas42/diple/releases/tag/v1.30.0")!

    @Test func homebrewRefreshesItsTapBeforeUpgrading() {
        let c = Updates.homebrewCommand(brew: "/opt/homebrew/bin/brew")
        let update = c.range(of: "update --quiet")!, upgrade = c.range(of: "upgrade --cask diple")!
        #expect(update.lowerBound < upgrade.lowerBound)
        #expect(!c.contains("pkill"))
        #expect(c.hasPrefix("set -e"))
    }

    @Test func anInstallThatLeftTheOldVersionOnDiskFailed() {
        let s = Updates.afterInstall(status: 0, onDisk: "1.29.2", installed: "1.29.2", version: "1.30.0", page: Self.page)
        #expect(s == .installFailed(version: "1.30.0", page: Self.page))
    }

    @Test func aFailingCommandFailed() {
        let s = Updates.afterInstall(status: 1, onDisk: "1.30.0", installed: "1.29.2", version: "1.30.0", page: Self.page)
        #expect(s == .installFailed(version: "1.30.0", page: Self.page))
    }

    @Test func aNewerVersionOnDiskIsInstalled() {
        let s = Updates.afterInstall(status: 0, onDisk: "1.30.0", installed: "1.29.2", version: "1.30.0", page: Self.page)
        #expect(s == .ready(version: "1.30.0"))
    }
}

@MainActor
struct UpdateDownloadTests {
    struct Release: Transport {
        func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
            let body = #"""
            {"tag_name":"v999.0.0","html_url":"https://github.com/chagas42/diple/releases/tag/v999.0.0",
             "assets":[
               {"name":"Diple-999.0.0.zip","size":4225651,"browser_download_url":"https://example.invalid/Diple-999.0.0.zip"},
               {"name":"Diple-999.0.0.zip.sha256","size":83,"browser_download_url":"https://example.invalid/Diple-999.0.0.zip.sha256"}
             ]}
            """#
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    static func zippedApp() async throws -> Data {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diple-zip-\(UUID().uuidString)")
        let app = dir.appendingPathComponent("Diple.app/Contents")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try "x".write(to: app.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let zip = dir.appendingPathComponent("Diple.zip")
        _ = await Shell.live.run("ditto", ["-c", "-k", "--keepParent", dir.appendingPathComponent("Diple.app").path, zip.path], dir, 60)
        return try Data(contentsOf: zip)
    }

    final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int64] = []
        func add(_ v: Int64) { lock.lock(); values.append(v); lock.unlock() }
        var all: [Int64] { lock.lock(); defer { lock.unlock() }; return values }
    }

    @Test func theReleaseNamesItsZipAndChecksum() async {
        let updates = Updates()
        updates.transport = Release()
        await updates.check()
        #expect(updates.asset?.zip.lastPathComponent == "Diple-999.0.0.zip")
        #expect(updates.asset?.checksum.lastPathComponent == "Diple-999.0.0.zip.sha256")
        #expect(updates.asset?.size == 4225651)
    }

    @Test func aDownloadReportsProgressAndEndsReadyToRestart() async throws {
        let zip = try await Self.zippedApp()
        let sum = SHA256Hex.of(zip) + "  Diple-999.0.0.zip\n"
        let seen = Seen()
        let updates = Updates()
        updates.transport = Release()
        updates.fetch = { url, progress in
            if url.lastPathComponent.hasSuffix(".sha256") { return Data(sum.utf8) }
            let half = Int64(zip.count / 2)
            progress(half, Int64(zip.count)); seen.add(half)
            progress(Int64(zip.count), Int64(zip.count)); seen.add(Int64(zip.count))
            return zip
        }
        await updates.check()
        guard case .available(let version, let page) = updates.state else { Issue.record("\(updates.state)"); return }
        await updates.download(version: version, page: page)
        #expect(updates.state == .ready(version: "999.0.0"))
        #expect(seen.all.count == 2)
        let staged = try #require(updates.staged)
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("Contents/Info.plist").path))
    }

    @Test func aChecksumThatDoesNotMatchInstallsNothing() async throws {
        let zip = try await Self.zippedApp()
        let updates = Updates()
        updates.transport = Release()
        updates.fetch = { url, _ in url.lastPathComponent.hasSuffix(".sha256") ? Data(String(repeating: "0", count: 64).utf8) : zip }
        await updates.check()
        guard case .available(let version, let page) = updates.state else { Issue.record("\(updates.state)"); return }
        await updates.download(version: version, page: page)
        guard case .installFailed = updates.state else { Issue.record("\(updates.state)"); return }
        #expect(updates.staged == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["DIPLE_LIVE_DOWNLOAD"] == "1"))
    func theRealLatestReleaseDownloadsVerifiesAndUnpacks() async throws {
        let updates = Updates()
        await updates.check()
        let asset = try #require(updates.asset)
        let seen = Seen()
        updates.fetch = { url, progress in
            try await Updates.liveFetch(url) { received, total in seen.add(received); progress(received, total) }
        }
        await updates.download(version: "live", page: Updates.releases)
        print("LIVE", asset.zip.lastPathComponent, "progress updates:", seen.all.count, "state:", updates.state)
        #expect(updates.state == .ready(version: "live"))
        #expect(seen.all.count > 10)
        let staged = try #require(updates.staged)
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("Contents/MacOS/Diple").path))
    }

    @Test func theSwapWaitsForDipleToQuitThenReplacesTheApp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("diple-swap-\(UUID().uuidString)")
        let staged = dir.appendingPathComponent("new/Diple.app")
        let dest = dir.appendingPathComponent("Applications/Diple.app")
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try "new".write(to: staged.appendingPathComponent("version"), atomically: true, encoding: .utf8)
        try "old".write(to: dest.appendingPathComponent("version"), atomically: true, encoding: .utf8)

        let r = await Shell.live.run("bash", ["-c", Updates.swapScript(opener: "true"), "swap", "999999", staged.path, dest.path], dir, 30)
        #expect(r.ok)
        #expect(try String(contentsOf: dest.appendingPathComponent("version"), encoding: .utf8) == "new")
    }
}

enum SHA256Hex {
    static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
