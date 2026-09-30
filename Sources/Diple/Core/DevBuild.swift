import Foundation

enum DevBuild {
    static var isOn: Bool {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String)?.hasSuffix("(Dev)") == true
    }
}
