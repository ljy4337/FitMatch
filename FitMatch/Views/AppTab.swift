import Foundation

enum AppTab: Hashable {
    case home
    case compare
    case history
    case recommend
    case my

    var logName: String {
        switch self {
        case .home:
            return "home"
        case .compare:
            return "compare"
        case .history:
            return "history"
        case .recommend:
            return "recommend"
        case .my:
            return "my"
        }
    }
}
