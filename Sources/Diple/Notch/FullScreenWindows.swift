import CoreGraphics

enum FullScreenWindows {
    static func ids(in spaces: Set<Int>) -> [CGWindowID] {
        guard !spaces.isEmpty,
              let all = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return all.compactMap { w in
            guard w[kCGWindowLayer as String] as? Int == 0,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  !spaces.isDisjoint(with: ManagedSpaces.spaces(of: id))
            else { return nil }
            return id
        }
    }

    static func anyOnScreen(_ ids: [CGWindowID]) -> Bool {
        guard !ids.isEmpty else { return false }
        var values = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &values, values.count, nil),
              let found = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
        else { return false }
        return found.contains { $0[kCGWindowIsOnscreen as String] as? Bool == true }
    }
}
