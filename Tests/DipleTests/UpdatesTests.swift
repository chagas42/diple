import Testing
import Foundation
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
}
