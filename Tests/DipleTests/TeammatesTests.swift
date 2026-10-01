import Foundation
import Testing
@testable import Diple

@Suite struct TeammatesTests {
    static func person(_ login: String) -> Person {
        Person(login: login, name: login, avatar: URL(string: "https://avatars.githubusercontent.com/\(login)")!)
    }

    static let org = ["alifoo", "DaniloFuchs", "trixkr"].map(person)

    @Test func theSignedInUserIsNotATeammate() {
        let logins = AppModel.others(Self.org, viewer: "danilofuchs").map(\.login)
        #expect(logins == ["alifoo", "trixkr"])
    }

    @Test func beforeTheViewerIsKnownEveryoneIsShown() {
        #expect(AppModel.others(Self.org, viewer: "").count == 3)
    }
}
