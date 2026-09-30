import Foundation

/// The authenticated root's nonvisual state machine. ContentView and
/// headless tests use this same action so a new account can never render the
/// previous account's cache while cache ownership is being prepared.
enum FitMatchAuthenticatedRootPresentation: Equatable {
    case checkingAuthentication
    case signIn
    case cachePreparationFailed(String)
    case preparingLocalCache
    case main
}

enum FitMatchAuthenticatedRootPresentationAction {
    static func presentation(
        authState: FitMatchAuthSessionState,
        localCachePreparedForUserID: UUID?,
        localCachePreparationErrorMessage: String?
    ) -> FitMatchAuthenticatedRootPresentation {
        switch authState {
        case .loading:
            return .checkingAuthentication
        case .signedOut:
            return .signIn
        case .signedIn(let userID):
            if let localCachePreparationErrorMessage {
                return .cachePreparationFailed(localCachePreparationErrorMessage)
            }
            return localCachePreparedForUserID == userID
                ? .main
                : .preparingLocalCache
        }
    }
}
